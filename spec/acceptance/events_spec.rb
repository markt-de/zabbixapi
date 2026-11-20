# Contract: ZabbixApi::Events live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/event
#   classes:  the write methods refuse and the events they named do not move | dump_by_id,
#             get_full_data, get_id and all against events this spec manufactured | a name that
#             repeats - across the fires of one run and across runs, since an event outlives the
#             trigger that made it - and what each read makes of it | get_full_data({}) running
#             unscoped | get_raw, one representative per kind of documented parameter: ids and a
#             field list, a state filter, a select, a sort, a count, a refusal | the wrapped
#             acknowledge through the guard: one event and the read surface showing it, both events
#             at once with every id back, and the close its trigger forbids | pending: tags [], a
#             lone problem_time bound | aftercare
#   not here: the hooks and the method list, the wire shape of every inherited read and every local
#             refusal, which the unit spec asserts offline; the six acknowledge actions beyond the
#             three below, whose task-manager operations would need waits this spec has no claim to
#             make; history.push, reached only as the guard's way to manufacture a problem;
#             non-trigger event sources, which come only from network discovery, agent
#             autoregistration and enabled service or internal actions, none of which this spec sets
#             up; trigger_severities, which matches an event by its trigger's current priority where
#             severities matches the event's own severity, so the two part on a recovery event,
#             whose severity reads 0, and after a re-severity or a change of the trigger's priority;
#             any server-wide count, which other triggers and the housekeeper move
require 'spec_helper'

RSpec.describe 'ZabbixApi::Events live', type: :acceptance do
  klass = 'events'

  before(:all) do
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'hostgroup')
    armed = Live::EventGuard.armed
    raise "#{armed.length} action(s) are enabled - a manufactured problem could notify or execute" unless armed.empty?

    @protected = Live::EventGuard.protect!
    @baseline = Live::EventGuard.baseline
    @fixture = Live::EventGuard.build(klass)
    @triggers = Live::EventGuard.own[:triggers]
    # The first push waits for the configuration cache to hold the trapper item, which the manual's
    # Zabbix trapper page allows up to 60 s, so it gets more than the default bound of 60 s. Firing
    # twice around a recovery leaves the closeable trigger with three events under one name:
    # problem, recovery, problem.
    Live::EventGuard.fire!(5, problems: 2, max: 150)
    Live::EventGuard.recover!
    opened = Live::EventGuard.fire!(5, problems: 2)
    @closeable = opened.find { |row| row['objectid'].to_i == @fixture[:closeable] }['eventid'].to_i
    @locked = opened.find { |row| row['objectid'].to_i == @fixture[:locked] }['eventid'].to_i
    @name = Live.one('event', eventids: [@closeable], output: ['name'])['name']
    # Read by name, not by our trigger id: an event outlives the trigger that made it until the
    # housekeeper removes it, as the event.get reference notes, so earlier runs of this spec may
    # have left events under the same name, and a lookup that filters on the name sees them too.
    @named = Live.get('event', filter: { name: @name }, output: ['eventid']).map { |event| event['eventid'].to_i }
  end

  after(:all) do
    begin
      open = Live.get('problem', objectids: Live::EventGuard.own[:triggers], output: ['eventid'])
      Live::EventGuard.recover! unless open.empty?
    rescue StandardError => e
      warn "  [after] our problems were not recovered: #{e.class}"
    end
    Live.teardown
  end

  let(:events) { Live.session.events }

  describe 'the write surface' do
    it 'refuses the five write methods by name, and both write aliases through the method they delegate to' do
      standing = @protected.first['eventid'].to_i
      expect { events.create(name: @name) }.to raise_error(ZabbixApi::ApiError, /Events#create is not supported/)
      expect { events.delete(standing) }.to raise_error(ZabbixApi::ApiError, /Events#delete is not supported/)
      expect { events.update({ eventid: standing, severity: 5 }, true) }.to raise_error(ZabbixApi::ApiError, /Events#update is not supported/)
      expect { events.create_or_update(name: @name) }.to raise_error(ZabbixApi::ApiError, /Events#create_or_update is not supported/)
      expect { events.get_or_create(name: @name) }.to raise_error(ZabbixApi::ApiError, /Events#get_or_create is not supported/)
      expect { events.add(name: @name) }.to raise_error(ZabbixApi::ApiError, /Events#create is not supported/)
      expect { events.destroy(standing) }.to raise_error(ZabbixApi::ApiError, /Events#delete is not supported/)
    end

    it 'leaves every problem it protected unchanged, and finds at least one' do
      expect(@protected).not_to be_empty
      expect(Live::EventGuard.changed(@baseline)).to eq([])
    end
  end

  describe 'the inherited reads' do
    it 'dump_by_id returns the one event of that id, a trigger event of our own trigger' do
      rows = Live.retrying('dump_by_id') { events.dump_by_id(eventid: @closeable) }
      expect(rows.map { |event| event['eventid'].to_i }).to eq([@closeable])
      expect([rows.first['source'], rows.first['object']]).to eq(%w[0 0])
      expect(rows.first['objectid'].to_i).to eq(@fixture[:closeable])
    end

    it 'get_full_data by name returns problem and recovery events alike, all under one name' do
      rows = Live.retrying('get_full_data') { events.get_full_data(name: @name) }
      expect(rows.map { |event| event['name'] }.uniq).to eq([@name])
      expect(rows.map { |event| event['eventid'].to_i }).to include(@closeable)
      expect(rows.map { |event| event['value'] }.uniq).to match_array(%w[0 1])
    end

    it 'get_full_data with an empty hash runs unscoped and reaches events this spec never created' do
      rows = Live.retrying('get_full_data unscoped') { events.get_full_data({}) }
      expect(rows.map { |event| event['eventid'].to_i }).to include(@closeable, @protected.first['eventid'].to_i)
    end

    it 'get_id refuses a name several events carry, and an eventid in the filter narrows it to one' do
      # No API method deletes an event, so every run adds more under this prefixed trigger name and
      # the count drifts: matched as a shape, never pinned. `value: 1` is no scope here for the same
      # reason - two accumulated problem events would make it ambiguous as well - so the eventid
      # scopes the lookup instead.
      expect { Live.retrying('get_id') { events.get_id(name: @name) } }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched \d+ event objects, not one \(eventid /)
      one = @named.first
      expect(Live.retrying('get_id scoped') { events.get_id(name: @name, eventid: one) }).to eq(one)
    end

    it 'get_id answers nil for a name no event carries' do
      expect(Live.retrying('get_id absent') { events.get_id(name: Live.name(klass, 'no-such-event')) }).to be_nil
    end

    it 'all maps the name to the Integer id of one of the events carrying it, and holds a single key for them all' do
      table = Live.retrying('all') { events.all }
      expect(table).to include(@name)
      expect(table[@name]).to be_a(Integer)
      expect(@named).to include(table[@name])
      expect(Live.count('event', objectids: [@fixture[:closeable]])).to be > 1
    end
  end

  describe 'get_raw, one representative per kind of documented parameter' do
    it 'narrows by eventids and returns the requested fields only' do
      rows = Live.retrying('get_raw ids') { events.get_raw(eventids: [@closeable, @locked], output: %w[eventid value]) }
      expect(rows.map { |event| event['eventid'].to_i }).to match_array([@closeable, @locked])
      expect(rows.first.keys.sort).to eq(%w[eventid value])
    end

    it 'narrows by the state filter: value 0 returns recovery events alone, and value 1 includes our two open problems' do
      recovered = Live.retrying('value 0') { events.get_raw(objectids: @triggers, value: 0, output: %w[eventid value]) }
      expect(recovered.map { |event| event['value'] }.uniq).to eq(['0'])
      problems = Live.retrying('value 1') { events.get_raw(objectids: @triggers, value: 1, output: %w[eventid value]) }
      expect(problems.map { |event| event['eventid'].to_i }).to include(@closeable, @locked)
    end

    it 'returns the fixture host under selectHosts, and the severity the trigger gave the event' do
      row = Live.retrying('selectHosts') { events.get_raw(eventids: [@closeable], output: ['severity'], selectHosts: %w[hostid host]) }.first
      expect(row['hosts'].map { |host| host['host'] }).to eq([Live::EventGuard.own[:host_name]])
      expect(row['severity']).to eq('2')
    end

    it 'sorts by eventid in both directions' do
      ascending = Live.retrying('sort asc') { events.get_raw(objectids: @triggers, sortfield: 'eventid', sortorder: 'ASC', output: ['eventid']) }.map { |event| event['eventid'].to_i }
      descending = Live.retrying('sort desc') { events.get_raw(objectids: @triggers, sortfield: 'eventid', sortorder: 'DESC', output: ['eventid']) }.map { |event| event['eventid'].to_i }
      expect(ascending).to eq(ascending.sort)
      expect(descending).to eq(ascending.reverse)
    end

    it 'counts the events of our two triggers and returns the count as a String' do
      count = Live.retrying('countOutput') { events.get_raw(objectids: @triggers, countOutput: true) }
      expect(count).to be_a(String)
      expect(count.to_i).to eq(Live.get('event', objectids: @triggers, output: ['eventid']).length)
    end

    it 'is refused for a sortfield the method does not offer' do
      expect { Live.retrying('get_raw bad sortfield') { events.get_raw(objectids: @triggers, sortfield: 'name', output: ['eventid']) } }.to raise_error(ZabbixApi::ApiError, %r{/sortfield})
    end
  end

  describe 'the acknowledge the gem wraps, reached through the guard' do
    it 'acknowledges our own event, answers Integer ids, and the read surface shows it' do
      answer = Live::EventGuard.ack!({ eventids: @closeable, action: 2 }, 'acknowledge')
      expect(answer).to eq([@closeable])
      expect(Live.one('event', eventids: [@closeable], output: ['acknowledged'])['acknowledged']).to eq('1')

      acknowledged = Live.retrying('acknowledged filter') { events.get_raw(objectids: @triggers, acknowledged: true, output: ['eventid']) }
      expect(acknowledged.map { |event| event['eventid'].to_i }).to eq([@closeable])
      row = Live.retrying('selectAcknowledges') { events.get_raw(eventids: [@closeable], output: ['eventid'], selectAcknowledges: 'extend') }.first
      expect(row['acknowledges'].map { |entry| entry['action'] }).to eq(['2'])
    end

    it 'returns every id as an Integer when one call adds a message to both events, and the message reads back' do
      answer = Live::EventGuard.ack!({ eventids: [@closeable, @locked], action: 4, message: 'zbxapi-spec note' }, 'message both')
      expect(answer).to match_array([@closeable, @locked])
      expect(answer).to all(be_an(Integer))

      rows = Live.retrying('selectAcknowledges both') { events.get_raw(eventids: [@closeable, @locked], output: ['eventid'], selectAcknowledges: 'extend') }
      expect(rows.flat_map { |event| event['acknowledges'].map { |entry| entry['message'] } }).to include('zbxapi-spec note')
    end

    it 'raises the server refusal of a close the trigger forbids, and that problem stays open' do
      expect { Live::EventGuard.ack!({ eventids: @locked, action: 1 }, 'close the locked one') }
        .to raise_error(ZabbixApi::ApiError, /trigger does not allow manual closing/)
      expect(Live.get('problem', objectids: @triggers, output: ['eventid']).map { |row| row['eventid'].to_i }).to include(@locked)
    end
  end

  describe 'documented get parameters the server does not honour' do
    it 'returns every event of our triggers for an empty tags array, as the event.get reference promises' do
      pending 'tags: [] returns no event at all, although the event.get reference says an empty array returns all'
      expect(events.get_raw(objectids: @triggers, tags: [], output: ['eventid']).length).to eq(Live.get('event', objectids: @triggers, output: ['eventid']).length)
    end

    it 'refuses a lone problem_time_till, which the event.get reference marks mandatory together with problem_time_from' do
      pending 'a lone bound is accepted and ignored, so the call answers with the unfiltered set'
      clock = Live.one('event', eventids: [@closeable], output: ['clock'])['clock'].to_i
      expect { Live.retrying('get_raw lone problem_time') { events.get_raw(objectids: @triggers, problem_time_till: clock - 1, output: ['eventid']) } }.to raise_error(ZabbixApi::ApiError, /Invalid parameter .*problem_time/)
    end
  end

  describe 'aftercare' do
    it 'leaves no problem of its triggers open, no host or host group under its prefix once torn down, every problem it protected unchanged, and the standing hosts and proxy still present' do
      Live::EventGuard.recover!
      expect(Live.get('problem', objectids: @triggers, output: ['eventid'])).to eq([])
      Live.teardown
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live::EventGuard.changed(@baseline)).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
