module Live
  # The guard for Events and Problems. The Events spec and recorder write in two ways: history.push
  # to manufacture a problem, event.acknowledge to move it through its states. event.acknowledge
  # names its events by id and push! allows history.push only its itemid form, so the question is
  # which ids may be named at all. Three layers: protection (every problem protect! records),
  # allowlist (only trigger events of the spec's own triggers on its own host, every asked-about id
  # known to the server), single route (ack! and push! are the only ways to the two writes). Every
  # wait is bounded.
  module EventGuard
    ITEM_KEY = 'zbxapi.spec.trap'.freeze
    WAIT_MAX = 60
    WAIT_STEP = 2

    @protected = []
    @own = { hg: nil, host: nil, host_name: nil, items: [], triggers: [] }

    class << self
      attr_reader :own

      # Every problem an unfiltered problem.get returns, before the fixture exists. Never written.
      def protect!
        problems = Live.get('problem', output: %w[eventid name objectid severity source object acknowledged suppressed])
        @protected = problems.map { |problem| problem['eventid'].to_i }
        problems
      end

      def protected?(id)
        @protected.include?(id.to_i)
      end

      # Every field of a protected event that one of the acknowledge actions could change, from both
      # tables the API exposes.
      def snapshot(eventid)
        event = Live.one('event', eventids: [eventid], selectAcknowledges: 'extend', selectSuppressionData: 'extend')
        raise "protected event #{eventid} is gone" if event.nil?

        problem = Live.one('problem', eventids: [eventid], selectAcknowledges: 'extend', selectSuppressionData: 'extend')
        {
          'event' => fields(event, 'acknowledged', 'severity', 'suppressed', 'r_eventid', 'cause_eventid', 'value', 'userid'),
          'problem' => fields(problem, 'acknowledged', 'severity', 'suppressed', 'r_eventid', 'cause_eventid', 'r_clock')
        }
      end

      def baseline
        @protected.to_h { |id| [id, snapshot(id)] }
      end

      # The protected events whose snapshot differs from the baseline; [] when nothing moved.
      def changed(before)
        @protected.reject { |id| snapshot(id) == before[id] }
      end

      def assert_unchanged!(before)
        moved = changed(before)
        raise "EVENT GUARD: protected event(s) #{moved.join(', ')} changed" unless moved.empty?

        true
      end

      # eventids as the API takes them - scalar or array, numeric or string - as Integers.
      def ids(value)
        Array(value).map { |item| Integer(item.to_s, 10) }
      end

      # Refuses unless every id is provably the spec's own. Returns the events read back.
      def own!(eventids, label)
        stray = eventids.select { |id| protected?(id) }
        raise "ack guard: #{label} names the protected event(s) #{stray.join(', ')}" unless stray.empty?

        found = Live.get('event', eventids: eventids, output: %w[eventid source object objectid], selectHosts: %w[hostid host])
        raise "ack guard: #{label} asked about #{eventids.length} event(s), the server knows #{found.length}" unless found.length == eventids.length

        found.each do |event|
          hosts = Array(event['hosts']).map { |host| host['hostid'].to_i }
          ours = event['source'] == '0' && event['object'] == '0' && @own[:triggers].include?(event['objectid'].to_i) && hosts == [@own[:host]]
          raise "ack guard: #{label} names event #{event['eventid']}, which is not ours (source #{event['source']}, object #{event['object']}, objectid #{event['objectid']}, hosts #{hosts.inspect})" unless ours
        end
        found
      end

      # The only route to event.acknowledge, through the gem's own Events#acknowledge, so what a
      # spec exercises here is the wrapper. It therefore answers an Array of Integer ids rather than
      # the server's {"eventids" => [...]}, and an empty list never reaches the server at all: the
      # wrapper refuses one locally, because the server accepts it and writes nothing.
      def ack!(payload, label, via: nil)
        list = ids(payload[:eventids] || payload['eventids'])
        own!(list, label) unless list.empty?
        (via || Live.session).events.acknowledge(payload)
      end

      # The only route to history.push: the itemid form, own items only.
      def push!(rows, label)
        list = rows.is_a?(Array) ? rows : [rows]
        list.each do |row|
          itemid = row[:itemid] || row['itemid']
          raise "push guard: #{label} uses the host+key form or names no item" if itemid.nil?
          raise "push guard: #{label} names item #{itemid}, not one of ours" unless @own[:items].include?(itemid.to_i)
        end
        Live.raw('history.push', list)
      end

      # Enabled actions of any event source; a run that manufactures a problem requires [] first.
      def armed
        Live.get('action', output: %w[actionid name eventsource status]).select { |action| action['status'] == '0' }
      end

      def until_event(eventid, what, max: WAIT_MAX)
        Live.wait("event #{eventid}: #{what}", max: max, step: WAIT_STEP) do
          event = Live.one('event', eventids: [eventid], selectAcknowledges: 'extend', selectSuppressionData: 'extend')
          event if event && yield(event)
        end
      end

      # An interface-less host in a group of its own, one trapper item, two last() triggers that
      # differ in manual_close and priority. Nothing polls, scans, notifies or executes; the triggers
      # are evaluated only when a value is pushed. Items and triggers go away with the host.
      def build(klass)
        session = Live.session
        @own[:hg] = Live.owns('hostgroup', Live.retrying('hostgroup.create') { session.hostgroups.create(name: Live.name(klass, 'hg')) })
        @own[:host_name] = Live.name(klass, 'h1')
        hostid = Live.retrying('host.create') do
          session.hosts.create(host: @own[:host_name], groups: [{ groupid: @own[:hg] }], description: 'spec fixture: no interface, one trapper item, two triggers', tags: [{ tag: 'zbxapi-spec', value: klass }])
        end
        @own[:host] = Live.owns('host', hostid)
        item = Live.retrying('item.create') do
          session.items.create(name: Live.name(klass, 'trap'), key_: ITEM_KEY, type: 2, value_type: 3, hostid: @own[:host], trapper_hosts: '0.0.0.0/0')
        end
        @own[:items] = [item]
        expression = "last(/#{@own[:host_name]}/#{ITEM_KEY})"
        closeable = Live.retrying('trigger closeable') do
          session.triggers.create(description: Live.name(klass, 'trg-closeable'), expression: "#{expression}>0", priority: 2, manual_close: 1)
        end
        locked = Live.retrying('trigger locked') do
          session.triggers.create(description: Live.name(klass, 'trg-locked'), expression: "#{expression}>1", priority: 4, manual_close: 0)
        end
        @own[:triggers] = [closeable, locked]
        { item: item, closeable: closeable, locked: locked }
      end

      # Push `value` until the server accepts it and `problems` of our triggers are in problem state.
      def fire!(value, problems:, max: WAIT_MAX)
        Live.wait("a pushed #{value} to be accepted and #{problems} problem(s) of ours to exist", max: max, step: WAIT_STEP) do
          push!({ itemid: @own[:items].first, value: value }, 'fire')
          open = Live.get('problem', objectids: @own[:triggers], output: %w[eventid objectid])
          open.length >= problems ? open : nil
        end
      end

      # Push 0 until no problem of ours is left. Always before teardown.
      def recover!
        Live.wait('every problem of ours to recover after a pushed 0', max: WAIT_MAX, step: WAIT_STEP) do
          push!({ itemid: @own[:items].first, value: 0 }, 'recover')
          Live.get('problem', objectids: @own[:triggers], output: %w[eventid]).empty? || nil
        end
      end

    private

      def fields(row, *keys)
        return nil if row.nil?

        row.slice(*keys).merge('acknowledges' => row['acknowledges'].length, 'suppression_data' => row['suppression_data'])
      end
    end
  end
end
