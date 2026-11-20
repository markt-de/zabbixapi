# Contract: ZabbixApi::Problems
#   evidence: spec/fixtures/problems/reads.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/problem
#   classes:  hooks, key overridden to eventid | the five CRUD methods and both aliases raise
#             locally and send nothing, whatever the arity | get_full_data: the six defaults and
#             three selects of a bare call, a caller's filter merged under the name shortcut, all 32
#             forwarded parameters, an explicit false kept, output overridable | the countOutput
#             branch drops sortfield and keeps sortorder, and the refusal it exists to avoid | all
#             is that builder's Array, in one request | the inherited reads: dump_by_id, get_raw,
#             get_id, and the get alias | key normalisation, three entry points | the two blind
#             lookups | a server refusal reaches error_message
#   not here: a write surface - problem.get is the one method the problem reference documents, so
#             there is neither a create, update or delete path to spec nor an unwrapped method to
#             note; what the forwarded parameters do on the server, which the acceptance spec
#             measures for a few representatives
require 'spec_helper'

RSpec.describe ZabbixApi::Problems do
  reads = Fixtures.exchanges('problems/reads')
  row = Fixtures.exchange('problems/reads', 'problem.get', 1)['result'].first
  dumped = Fixtures.exchange('problems/reads', 'problem.get', 11)['result']
  identified = Fixtures.exchange('problems/reads', 'problem.get', 9)['result']
  eventid = row['eventid'].to_i
  name = row['name']

  # What problem.get carries when the caller passes nothing: the three documented defaults the
  # builder restates (source, object, evaltype), the sort it invents, the output default and the
  # three hardcoded selects. compact_params drops the emptied name filter and every other nil.
  fixed = {
    'source' => 0, 'object' => 0, 'evaltype' => 0, 'sortfield' => %w[eventid], 'sortorder' => 'DESC',
    'output' => 'extend', 'selectAcknowledges' => 'extend', 'selectTags' => 'extend',
    'selectSuppressionData' => 'extend'
  }

  # Twenty-two of the 32 parameters the builder forwards, spelled out from the problem.get reference
  # so a parameter it stops forwarding fails here; each differs from the class's own default where
  # it has one, but for sortfield, whose one documented value is that default. `name` is the
  # twenty-third and becomes the filter instead of a parameter of its own.
  settable = {
    name: name, eventids: [eventid], groupids: [4], hostids: [10084], objectids: [22391],
    source: 3, object: 4, acknowledged: true, action: 2, action_userids: [1],
    suppressed: true, symptom: true, severities: [3, 4], evaltype: 2,
    tags: [{ tag: 'scope', value: 'availability' }], recent: true,
    eventid_from: '20', eventid_till: '30', time_from: 1787926766, time_till: 1787930000,
    sortfield: %w[eventid], sortorder: 'ASC', countOutput: false
  }

  let(:client) { FakeClient.new(reads) }
  let(:problems) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'problem', identify: 'name', key: 'eventid', keys: 'eventids', default_options: {}
  it_behaves_like 'a read-only wrapper', message: /is not supported: the Zabbix problem API only provides problem\.get/

  it_behaves_like 'an inherited get_id', identify: 'name', key: 'eventid', value: name, rows: identified
  it_behaves_like 'the inherited reads', identify: 'name', key: 'eventid', value: name, id: eventid, rows: dumped, except: [:get_full_data]
  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'eventid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per entry point that reads a caller's hash: the class's own builder, and the two
  # inherited lookups. create and update normalise nothing here, both being refusals, and `all`
  # takes no argument at all.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: reads
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: reads
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { eventid: eventid }, exchanges: reads

  describe 'the write surface' do
    it 'raises ApiError rather than ArgumentError when a refused method is called with no argument' do
      expect { problems.create }.to raise_error(ZabbixApi::ApiError, /only provides problem\.get/)
      expect(client.calls).to be_empty
    end
  end

  describe '#get_full_data' do
    it 'sends the six defaults and three selects and nothing else when the caller passes nothing' do
      problems.get_full_data({})
      expect(client.sent('problem.get').last).to eq(fixed)
    end

    it 'turns the identify value into a name filter beside them' do
      problems.get_full_data(name: name)
      expect(client.sent('problem.get').last).to eq(fixed.merge('filter' => { 'name' => name }))
    end

    it 'returns the rows the server sent, with the three hardcoded selects among them' do
      fake = FakeClient.new([Fixtures.exchange('problems/reads', 'problem.get', 1)])
      rows = described_class.new(fake).get_full_data(name: name)
      expect(rows).to eq(Fixtures.exchange('problems/reads', 'problem.get', 1)['result'])
      expect(rows.first).to include('acknowledges', 'tags', 'suppression_data')
    end

    it 'returns the empty Array the server sent for a name no problem carries' do
      fake = FakeClient.new([Fixtures.exchange('problems/reads', 'problem.get', 3)])
      expect(described_class.new(fake).get_full_data(name: 'zbxapi-spec-problems-no-such-problem')).to eq([])
    end

    it 'forwards 22 caller-settable parameters, the caller winning over its own defaults' do
      problems.get_full_data(settable)
      expect(client.sent('problem.get').last).to eq(
        'filter' => { 'name' => name },
        'eventids' => [eventid], 'groupids' => [4], 'hostids' => [10084], 'objectids' => [22391],
        'source' => 3, 'object' => 4, 'acknowledged' => true, 'action' => 2, 'action_userids' => [1],
        'suppressed' => true, 'symptom' => true, 'severities' => [3, 4], 'evaltype' => 2,
        'tags' => [{ 'tag' => 'scope', 'value' => 'availability' }], 'recent' => true,
        'eventid_from' => '20', 'eventid_till' => '30', 'time_from' => 1787926766, 'time_till' => 1787930000,
        'sortfield' => %w[eventid], 'sortorder' => 'ASC', 'countOutput' => false,
        'output' => 'extend', 'selectAcknowledges' => 'extend', 'selectTags' => 'extend',
        'selectSuppressionData' => 'extend'
      )
    end

    it 'keeps an explicit false for acknowledged, suppressed and symptom' do
      problems.get_full_data(acknowledged: false, suppressed: false, symptom: false)
      sent = client.sent('problem.get').last
      expect([sent['acknowledged'], sent['suppressed'], sent['symptom']]).to eq([false, false, false])
      expect(sent).to eq(fixed.merge('acknowledged' => false, 'suppressed' => false, 'symptom' => false))
    end

    it 'forwards filter, search, searchByAny, searchWildcardsEnabled, startSearch, excludeSearch, editable, limit and preservekeys, a caller filter merging with the name shortcut' do
      problems.get_full_data(name: name, filter: { severity: 3 }, search: { name: name }, searchByAny: true,
                             searchWildcardsEnabled: true, startSearch: true, excludeSearch: true,
                             editable: true, limit: 1, preservekeys: true)
      expect(client.sent('problem.get').last).to eq(
        fixed.merge(
          'filter' => { 'severity' => 3, 'name' => name },
          'search' => { 'name' => name }, 'searchByAny' => true, 'searchWildcardsEnabled' => true,
          'startSearch' => true, 'excludeSearch' => true, 'editable' => true, 'limit' => 1,
          'preservekeys' => true
        )
      )
    end

    it 'lets a top-level name win over one the caller put inside the filter' do
      problems.get_full_data(name: name, filter: { name: 'other' })
      expect(client.sent('problem.get').last['filter']).to eq('name' => name)
    end

    it 'lets the caller narrow output, while the three selects stay fixed' do
      problems.get_full_data(output: %w[eventid name])
      sent = client.sent('problem.get').last
      expect(sent['output']).to eq(%w[eventid name])
      expect(sent.values_at('selectAcknowledges', 'selectTags', 'selectSuppressionData')).to eq(%w[extend extend extend])
    end
  end

  describe '#get_full_data with countOutput' do
    it 'drops sortfield, keeps sortorder, and returns the count as the String the server sent' do
      counted = Fixtures.exchange('problems/reads', 'problem.get', 7)
      fake = FakeClient.new([counted])

      expect(described_class.new(fake).get_full_data(countOutput: true)).to eq(counted['result'])
      sent = fake.sent('problem.get').last
      expect(sent).not_to have_key('sortfield')
      expect([sent['countOutput'], sent['sortorder']]).to eq([true, 'DESC'])
    end

    it 'keeps sortfield when countOutput is explicitly false, the guard reading the value and not the key' do
      problems.get_full_data(countOutput: false)
      expect(client.sent('problem.get').last).to eq(fixed.merge('countOutput' => false))
    end

    it 'raises ApiError carrying the server reason in error_message, for get_raw with both countOutput and sortfield' do
      refused = Fixtures.exchange('problems/reads', 'problem.get', 15)
      fake = FakeClient.new([refused])

      expect { described_class.new(fake).get_raw(countOutput: true, sortfield: %w[eventid]) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/Database error occurred/) }
    end
  end

  describe '#all' do
    it "returns the builder's Array of problem objects, in one request" do
      table = Fixtures.exchange('problems/reads', 'problem.get')
      fake = FakeClient.new([table])

      result = described_class.new(fake).all
      expect(result).to be_an(Array)
      expect(result).to eq(table['result'])
      expect(result.first).to include('eventid', 'name')
      expect(fake.sent('problem.get')).to eq([fixed])
    end
  end

  describe 'the get alias' do
    it 'sends exactly what get_full_data sends and returns the same rows' do
      via_alias = FakeClient.new(reads)
      via_method = FakeClient.new(reads)

      expect(described_class.new(via_alias).get(name: name)).to eq(described_class.new(via_method).get_full_data(name: name))
      expect(via_alias.calls).to eq(via_method.calls)
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused sortfield, filter and source' do
      [
        [13, { sortfield: %w[clock] }, /value must be "eventid"/],
        [14, { filter: { suppressed: 0 } }, /unexpected parameter "suppressed"/],
        [16, { source: 9 }, /value must be one of 0, 3, 4/]
      ].each do |index, params, reason|
        fake = FakeClient.new([Fixtures.exchange('problems/reads', 'problem.get', index)])
        expect { described_class.new(fake).get_raw(params) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
