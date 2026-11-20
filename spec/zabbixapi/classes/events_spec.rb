# Contract: ZabbixApi::Events
#   evidence: spec/fixtures/events/reads.json, spec/fixtures/events/acknowledge.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/event
#   classes:  hooks | the five write methods and both write aliases refuse locally and send nothing,
#             a write method naming itself and an alias the method it delegates to | the five
#             inherited reads and what each sends | get_id refuses when a name repeats, and a
#             scoping key rides in the filter | all maps the name to an Integer id and collapses
#             every repeat | the get alias | get_raw return shapes: rows, a String count, a select*
#             passthrough | blind lookups | key normalisation at four entry points, one per
#             mechanism | a refused event.get carries the server reason in error_message |
#             acknowledge: the bare object on the wire, every id back as an Integer, the local
#             refusal of an empty list, and a refusal the server makes
#   not here: history.push, which the gem does not wrap; the wire shapes of create, delete and
#             update, which this class can never send, and with them the update skip, the upserts
#             and the delegation of add and destroy to a method that exists; the server behaviour of
#             event.get, such as the source and object defaults of 0, the empty tags array and the
#             lone problem_time bound, the last two measured by the acceptance spec against the live
#             server
require 'spec_helper'

RSpec.describe ZabbixApi::Events do
  reads = Fixtures.exchanges('events/reads')
  problem = Fixtures.exchange('events/reads', 'event.get')['result'].first
  same_name = Fixtures.exchange('events/reads', 'event.get', 1)['result']
  selected = Fixtures.exchange('events/reads', 'event.get', 5)
  counted = Fixtures.exchange('events/reads', 'event.get', 6)
  refused = Fixtures.exchange('events/reads', 'event.get', 7)
  acknowledged = Fixtures.exchange('events/acknowledge', 'event.acknowledge')
  bulk = Fixtures.exchange('events/acknowledge', 'event.acknowledge', 1)
  repeated = Fixtures.exchange('events/acknowledge', 'event.acknowledge', 2)
  refused_ack = Fixtures.exchange('events/acknowledge', 'event.acknowledge', 3)
  ack_id = acknowledged['params']['eventids']
  id = problem['eventid'].to_i
  name = problem['name']

  let(:client) { FakeClient.new(reads) }
  let(:events) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'event', identify: 'name', key: 'eventid', keys: 'eventids', default_options: {}
  it_behaves_like 'a read-only wrapper', message: /is not supported: the Zabbix event API only provides event\.get and event\.acknowledge/

  it_behaves_like 'the inherited reads', identify: 'name', key: 'eventid', value: name, id: id, rows: [problem]
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'eventid', value: name, rows: [problem]
  it_behaves_like 'an inherited all', identify: 'name', key: 'eventid', rows: [problem]

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'eventid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism, not per entry point. The five write methods raise
  # before they could normalise anything, so what is left is the plain symbolize_keys of a
  # filter-building read, the conditional one in get_id, require_field! in dump_by_id, and
  # acknowledge, which symbolizes before it decides whether it was given an eventid at all.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: reads
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: reads
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { eventid: id }, exchanges: reads
  it_behaves_like 'a key-normalising entry point', method: :acknowledge, payload: { eventids: ack_id, action: 2 }, exchanges: [acknowledged]

  describe 'the class' do
    it 'overrides the two hooks and the five write methods, and adds acknowledge' do
      expect(described_class.instance_methods(false).sort).to eq([:acknowledge, :create, :create_or_update, :delete, :get_or_create, :identify, :method_name, :update])
    end
  end

  describe 'the refusals' do
    it 'names the method the caller called' do
      { create: [{ name: name }], delete: [id], update: [{ eventid: id, severity: 5 }, true], create_or_update: [{ name: name }], get_or_create: [{ name: name }] }.each do |method, args|
        expect { events.public_send(method, *args) }.to raise_error(ZabbixApi::ApiError, /Events##{method} is not supported/)
      end
      expect(client.calls).to be_empty
    end

    it 'lets the write aliases raise through the method they delegate to' do
      expect { events.add(name: name) }.to raise_error(ZabbixApi::ApiError, /Events#create is not supported/)
      expect { events.destroy(id) }.to raise_error(ZabbixApi::ApiError, /Events#delete is not supported/)
      expect(client.calls).to be_empty
    end
  end

  describe '#acknowledge' do
    it 'sends the payload as a bare object and answers Integer ids' do
      fake = FakeClient.new([acknowledged])
      expect(described_class.new(fake).acknowledge(eventids: ack_id, action: 2)).to eq([ack_id])
      expect(fake.sent('event.acknowledge')).to eq([{ 'eventids' => ack_id, 'action' => 2 }])
    end

    it 'returns every id the server updated' do
      ids = bulk['params']['eventids']
      expect(ids.length).to be > 1
      expect(described_class.new(FakeClient.new([bulk])).acknowledge(eventids: ids, action: 4, message: bulk['params']['message'])).to eq(ids)
    end

    it 'answers the id again for an action the event already carries' do
      expect(described_class.new(FakeClient.new([repeated])).acknowledge(eventids: ack_id, action: 2)).to eq([ack_id])
    end

    it 'refuses an empty, absent or nil eventids locally and sends nothing' do
      [{ eventids: [], action: 2 }, { action: 2 }, { eventids: nil, action: 2 }].each do |payload|
        expect { events.acknowledge(payload) }.to raise_error(ZabbixApi::ApiError, /Events#acknowledge was given no eventid/)
      end
      expect(client.calls).to be_empty
    end

    it 'raises ApiError carrying the server reason in error_message, for a refused acknowledge' do
      expect { described_class.new(FakeClient.new([refused_ack])).acknowledge(refused_ack['params']) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/trigger does not allow manual closing/) }
    end
  end

  describe '#get' do
    it 'is get_full_data: the same request and the same rows' do
      through_alias = FakeClient.new(reads)
      expect(described_class.new(through_alias).get(name: name)).to eq(events.get_full_data(name: name))
      expect(through_alias.calls).to eq(client.calls)
    end
  end

  describe '#get_id' do
    it 'refuses to choose among the rows carrying the name' do
      expect(same_name.map { |event| event['name'] }.uniq).to eq([name])
      expect(same_name.length).to be > 1

      repeated = FakeClient.new([{ method: 'event.get', result: same_name }])
      ids = same_name.map { |event| event['eventid'] }.uniq
      expect { described_class.new(repeated).get_id(name: name) }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched #{ids.size} event objects, not one \(eventid #{ids.join(', ')}\): narrow the lookup\z/)
    end

    it 'carries a scoping key into the filter' do
      scoped = FakeClient.new([{ method: 'event.get', result: [problem] }])
      described_class.new(scoped).get_id(name: name, value: 1)
      expect(scoped.sent('event.get').last).to eq('filter' => { 'name' => name, 'value' => 1 }, 'output' => %w[eventid name])
    end
  end

  describe '#all' do
    it 'keeps one key per name, so every repeat is lost and the last row the server listed wins' do
      table = FakeClient.new([{ method: 'event.get', result: same_name }])
      expect(described_class.new(table).all).to eq(name => same_name.last['eventid'].to_i)
    end
  end

  describe '#get_raw' do
    it 'returns the count as the String the server sent' do
      counting = FakeClient.new([counted])
      answer = described_class.new(counting).get_raw(objectids: [problem['objectid']], countOutput: true)
      expect(answer).to be_a(String)
      expect(answer).to eq(counted['result'])
    end

    it 'passes a select* parameter through untouched and returns the property each select promises' do
      selecting = FakeClient.new([selected])
      row = described_class.new(selecting).get_raw(eventids: [id], output: ['eventid'], selectAcknowledges: 'extend', selectHosts: %w[hostid host], selectTags: 'extend').first
      expect(selecting.sent('event.get').last).to eq('eventids' => [id], 'output' => ['eventid'], 'selectAcknowledges' => 'extend', 'selectHosts' => %w[hostid host], 'selectTags' => 'extend')
      expect(row.keys).to match_array(%w[eventid acknowledges hosts tags])
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError whose error_message names the parameter the server rejected' do
      expect { described_class.new(FakeClient.new([refused])).get_raw(sortfield: 'name', output: ['eventid']) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(%r{/sortfield}) }
    end
  end
end
