# Contract: ZabbixApi::Problems live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/problem
#   classes:  the seven write entry points refuse locally and the problem stands unchanged |
#             get_full_data reads the standing problem by name, with the three hardcoded selects
#             present | a forwarded flag narrows in both directions | a forwarded list narrows | a
#             forwarded filter narrows likewise, and preservekeys rekeys the result | output can be
#             narrowed | countOutput through the class returns a count | get_id, dump_by_id, all |
#             one get_raw representative per kind: a select in its count form, sortfield accepted
#             and refused, the filter whitelist | pending: a filter on suppressed, tags [],
#             countOutput beside sortfield | aftercare
#   not here: a problem of the spec's own, acknowledged, suppressed, ranked as a symptom and closed,
#             with the parameters and properties only such a problem exercises, which would measure
#             server behaviour at the price of two write paths: history.push, which the gem does not
#             wrap, and event.acknowledge; media types with an event menu entry, which fill urls,
#             and a User-type session, which may call problem.get, sees no problem on a host it
#             cannot read and is refused problem.get under a role denying it, which measure
#             mediatype, permission and role behaviour rather than this wrapper; the hooks and the
#             request get_full_data builds, which are the unit spec's, traffic not being observable
#             here; that an unfiltered read returns exactly one row, a server-wide count
require 'spec_helper'

RSpec.describe 'ZabbixApi::Problems live', type: :acceptance do
  klass = 'problems'

  before(:all) do
    # This class creates nothing: problem.get is its whole surface, and the standing problem is the
    # read fixture. protect! records it and every other problem an unfiltered problem.get returns,
    # so the aftercare example can prove none of them moved.
    Live::EventGuard.protect!
    @baseline = Live::EventGuard.baseline
    host = Live.one('host', filter: { host: Live::STANDING_PROBLEM_HOST }, output: %w[hostid host])
    raise "the stock host #{Live::STANDING_PROBLEM_HOST}, which carries the standing problem, is not on this server" if host.nil?

    @standing = Live.one('problem', hostids: [host['hostid'].to_i], selectTags: 'extend')
    raise "no problem stands on #{Live::STANDING_PROBLEM_HOST}; this class has no read fixture without one" if @standing.nil?

    @eventid = @standing['eventid'].to_i
    @name = @standing['name']
    @severity = @standing['severity'].to_i
  end

  after(:all) { Live.teardown }

  let(:problems) { Live.session.problems }

  def ids(rows)
    Array(rows).map { |row| row['eventid'].to_i }
  end

  describe 'the write surface' do
    it 'refuses all seven entry points locally and leaves the problem exactly as it was' do
      before_state = Live.one('problem', eventids: [@eventid])
      [
        -> { problems.create(name: @name) },
        -> { problems.add(name: @name) },
        -> { problems.delete(@eventid) },
        -> { problems.destroy(@eventid) },
        -> { problems.update({ eventid: @eventid, severity: 5 }, true) },
        -> { problems.create_or_update(name: @name, severity: 5) },
        -> { problems.get_or_create(name: @name) }
      ].each do |call|
        expect { call.call }.to raise_error(ZabbixApi::ApiError, /only provides problem\.get/)
      end
      expect(Live.one('problem', eventids: [@eventid])).to eq(before_state)
    end
  end

  describe '#get_full_data' do
    it 'returns the standing problem under its name, with the three hardcoded selects present' do
      rows = Live.retrying('get_full_data name') { problems.get_full_data(name: @name) }
      found = rows.find { |row| row['eventid'].to_i == @eventid }
      expect(found).not_to be_nil
      expect(found).to include('acknowledges', 'tags', 'suppression_data')
      expect(found['tags']).to all(include('tag', 'value'))
      expect(found['severity'].to_i).to eq(@severity)
    end

    it 'returns an empty Array for a name no problem carries' do
      expect(Live.retrying('get_full_data absent') { problems.get_full_data(name: Live.name(klass, 'no-such-problem')) }).to eq([])
    end

    it 'forwards acknowledged, so an unacknowledged problem answers to false and not to true' do
      expect(ids(Live.retrying('acknowledged false') { problems.get_full_data(acknowledged: false) })).to include(@eventid)
      expect(ids(Live.retrying('acknowledged true') { problems.get_full_data(acknowledged: true) })).not_to include(@eventid)
    end

    it 'forwards severities, so the problem answers to its own severity and not to another' do
      expect(ids(Live.retrying('severities own') { problems.get_full_data(severities: [@severity]) })).to include(@eventid)
      expect(ids(Live.retrying('severities other') { problems.get_full_data(severities: [(@severity + 1) % 6]) })).not_to include(@eventid)
    end

    it 'forwards preservekeys, so the result comes back keyed by eventid rather than as an Array' do
      kept = Live.retrying('preservekeys forwarded') { problems.get_full_data(eventids: [@eventid], preservekeys: true) }
      expect(kept).to be_a(Hash)
      expect(kept.keys).to eq([@eventid.to_s])
    end

    it 'forwards a caller filter, so the problem answers to a filter on its own severity and not on another' do
      expect(ids(Live.retrying('filter own severity') { problems.get_full_data(eventids: [@eventid], filter: { severity: @severity }) })).to eq([@eventid])
      expect(ids(Live.retrying('filter other severity') { problems.get_full_data(eventids: [@eventid], filter: { severity: (@severity + 1) % 6 }) })).to eq([])
    end

    it 'forwards output, so the caller narrows the row while the three selects stay' do
      row = Live.retrying('output narrowed') { problems.get_full_data(eventids: [@eventid], output: %w[eventid]) }.first
      expect(row.keys).to include('eventid', 'acknowledges', 'tags', 'suppression_data')
      expect(row.keys).not_to include('name', 'severity', 'clock')
    end
  end

  describe 'countOutput' do
    it 'returns the count as a String' do
      count = Live.retrying('countOutput') { problems.get_full_data(eventids: [@eventid], countOutput: true) }
      expect(count).to be_a(String)
      expect(count).to eq('1')
    end

    it 'is accepted beside sortfield, both being documented parameters of the method' do
      pending 'problem.get answers "Database error occurred." for countOutput together with sortfield, and names neither'
      expect(problems.get_raw(eventids: [@eventid], countOutput: true, sortfield: %w[eventid])).to eq('1')
    end
  end

  describe 'the inherited reads' do
    it 'get_id resolves the name to the eventid as an Integer' do
      expect(Live.retrying('get_id') { problems.get_id(name: @name) }).to eq(@eventid)
    end

    it 'get_id returns nil for a name no problem carries' do
      expect(Live.retrying('get_id absent') { problems.get_id(name: Live.name(klass, 'no-such-problem')) }).to be_nil
    end

    it 'dump_by_id returns the one problem its eventid names' do
      expect(ids(Live.retrying('dump_by_id') { problems.dump_by_id(eventid: @eventid) })).to eq([@eventid])
    end

    it 'all returns an Array of problem objects holding the standing problem, not a name-to-id Hash' do
      table = Live.retrying('all') { problems.all }
      expect(table).to be_an(Array)
      expect(ids(table)).to include(@eventid)
      expect(table.first).to include('eventid', 'name', 'severity')
    end
  end

  describe '#get_raw' do
    it 'passes a select through in its count form' do
      row = Live.retrying('selectAcknowledges count') { problems.get_raw(eventids: [@eventid], output: %w[eventid], selectAcknowledges: 'count') }.first
      expect(row['acknowledges']).to eq('0')
    end

    it 'accepts sortfield eventid, the one value the problem.get reference documents, and is refused for clock' do
      expect(ids(Live.retrying('sortfield eventid') { problems.get_raw(eventids: [@eventid], output: %w[eventid], sortfield: %w[eventid]) })).to eq([@eventid])
      expect { Live.retrying('sortfield clock') { problems.get_raw(sortfield: %w[clock]) } }.to raise_error(ZabbixApi::ApiError, %r{/sortfield.*value must be})
    end

    it 'filters on eventid' do
      expect(ids(Live.retrying('filter eventid') { problems.get_raw(filter: { eventid: @eventid }, output: %w[eventid]) })).to eq([@eventid])
    end

    it 'filters on suppressed, an integer property of the problem object' do
      pending 'problem.get filter is an undocumented whitelist of 11 of the 18 properties, and refuses suppressed as an unexpected parameter'
      expect(ids(problems.get_raw(filter: { suppressed: 0 }, output: %w[eventid]))).to include(@eventid)
    end

    it 'returns the standing problem for an empty tags array, which the problem.get reference says returns all problems' do
      pending 'the problem.get reference promises that an empty tags array returns all problems; problem.get returns none, as event.get does for the same sentence of its own reference'
      expect(ids(problems.get_raw(tags: [], output: %w[eventid]))).to include(@eventid)
    end
  end

  describe 'aftercare' do
    it 'leaves every problem it protected unchanged and no host under its prefix once torn down, and the standing hosts and proxy still present' do
      Live.teardown
      expect(Live::EventGuard.changed(@baseline)).to eq([])
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
