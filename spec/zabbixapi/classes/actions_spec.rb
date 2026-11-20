# Contract: ZabbixApi::Actions
#   evidence: spec/fixtures/actions/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/action
#   classes:  hooks, key and keys derived, one overridden read | create wraps one object and merges
#             no defaults | get_full_data adds four selects beside filter and output | its filter is
#             dropped when no name is given, and a string-keyed name narrows it like any other |
#             dump_by_id asks for extend alone, so none of the four collections is in the dump and a
#             payload naming one is never skipped | get_raw passes through | get_id filters on the
#             whole payload | all maps the name to an Integer id | update skips an equal payload,
#             issues a differing one, honours force | the four upsert branches, the id merged in as
#             a String | the three aliases | delete sends a bare id | key normalisation, four
#             inherited entry points, four mechanisms | refusals: the server's on the first request
#             and on the second, the two local guards
#   not here: the server's refusals - duplicate name, missing name, missing operations, a message
#             operation without recipients, an operation type the event source forbids, read-only
#             actionid, eventsource out of the enum, a gated esc_period, esc_period below 60 s, an
#             id no action carries - which are server behaviour and belong to the acceptance spec;
#             one create refusal and one update refusal are kept here as the two error paths through
#             the gem, their remaining exchanges stay in the fixture for the wording the acceptance
#             spec matches | the condition-type and operation-type matrices, likewise server
#             behaviour | bulk arrays, which Basic#create and #delete handle and Basic's own spec
#             covers | the aliases' read side beyond delegation, which is get_full_data's | no
#             host-scoped upsert: actions have no hostid, so Basic's own pair applies unchanged
require 'spec_helper'

RSpec.describe ZabbixApi::Actions do
  crud = Fixtures.exchanges('actions/crud')
  # The whole table, as the read whose filter was dropped answered it.
  table = Fixtures.exchange('actions/crud', 'action.get', 1)['result']
  lookup_row = Fixtures.exchange('actions/crud', 'action.get', 2)['result'].first
  dump_row = Fixtures.exchange('actions/crud', 'action.get', 4)['result'].first
  id = dump_row['actionid'].to_i
  name = dump_row['name']
  # The four selects the override adds, none of which output: extend returns by itself.
  selects = { 'selectOperations' => 'extend', 'selectRecoveryOperations' => 'extend', 'selectUpdateOperations' => 'extend', 'selectFilter' => 'extend' }
  # An operation of the spec's own, never sent anywhere: it stands for any related collection the
  # dump cannot show, and its ids are arbitrary because no server ever sees them.
  message_op = { operationtype: 0, opmessage: { default_msg: 1, mediatypeid: 42 }, opmessage_grp: [{ usrgrpid: 43 }] }

  let(:client) { FakeClient.new(crud) }
  let(:actions) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'action', identify: 'name', key: 'actionid', keys: 'actionids', default_options: {}

  it_behaves_like 'an inherited create', payload: { name: name, eventsource: 0, status: 1 }, defaults: {}, exchange: Fixtures.exchange('actions/crud', 'action.create')
  it_behaves_like 'an inherited delete', id: Fixtures.exchange('actions/crud', 'action.delete', 1)['params'].first, exchange: Fixtures.exchange('actions/crud', 'action.delete', 1)
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'actionid', value: name, rows: [lookup_row]
  it_behaves_like 'an inherited all', identify: 'name', key: 'actionid', rows: table
  # except: get_full_data, the one read this class overrides; its own examples are below.
  it_behaves_like 'the inherited reads', identify: 'name', key: 'actionid', value: name, id: id, rows: [dump_row], except: [:get_full_data]
  # operations, recovery_operations, update_operations and filter all replace, and none of them is
  # in extend, so operations stands for the four.
  it_behaves_like 'an update that skips when unchanged', key: 'actionid', id: id, dump: [dump_row], unchanged: { status: 1 }, changed: { esc_period: '2h' }, collection: { operations: [message_op] }
  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'actionid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism of the four inherited entry points - the plain
  # symbolize_keys in create, the conditional symbolize in get_id, require_field! in dump_by_id, the
  # dump comparison in update - plus get_full_data, whose override symbolizes the keys itself.
  it_behaves_like 'a key-normalising entry point', method: :create, payload: { name: name, eventsource: 0, status: 1 }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: [Fixtures.exchange('actions/crud', 'action.get')]
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { actionid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { actionid: id, status: 1 }, exchanges: crud

  describe '#get_full_data' do
    it 'asks for the four collections by name' do
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.get')])

      described_class.new(fake).get_full_data(name: name)
      expect(fake.sent('action.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => 'extend' }.merge(selects)])
    end

    it 'returns the one action, carrying the four properties the selects add' do
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.get')])

      returned = described_class.new(fake).get_full_data(name: name)
      expect(returned.map { |action| action['name'] }).to eq([name])
      expect(returned.first.keys).to include('operations', 'recovery_operations', 'update_operations', 'filter')
    end

    it 'drops the whole filter when the payload names nothing, rather than sending a null name' do
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.get', 1)])

      described_class.new(fake).get_full_data({})
      expect(fake.sent('action.get')).to eq([{ 'output' => 'extend' }.merge(selects)])
    end

    it 'normalises a string-keyed name into the filter, so the call narrows to the one action' do
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.get')])

      returned = described_class.new(fake).get_full_data('name' => name)
      expect(fake.sent('action.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => 'extend' }.merge(selects)])
      expect(returned.map { |action| action['name'] }).to eq([name])
    end
  end

  describe '#dump_by_id' do
    it 'asks for extend alone, so the dump carries none of the four collections' do
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.get', 4)])

      dumped = described_class.new(fake).dump_by_id(actionid: id)
      expect(fake.sent('action.get')).to eq([{ 'filter' => { 'actionid' => id }, 'output' => 'extend' }])
      expect(dumped.first.keys).not_to include('operations', 'recovery_operations', 'update_operations', 'filter')
    end
  end

  describe '#update' do
    it 'raises before any request when the payload carries no actionid, naming the guard it came from' do
      expect { actions.update(name: name) }.to raise_error(ZabbixApi::ApiError, /actionid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end
  end

  describe '#create_or_update' do
    it 'looks the name up, dumps the action and updates it with the id merged in as a String' do
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.get', 12), Fixtures.exchange('actions/crud', 'action.get', 13), Fixtures.exchange('actions/crud', 'action.update', 3)])

      expect(described_class.new(fake).create_or_update(name: name, esc_period: '3h')).to eq(id)
      expect(fake.sent('action.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => %w[actionid name] },
                                             { 'filter' => { 'actionid' => id.to_s }, 'output' => 'extend' }])
      expect(fake.sent('action.update')).to eq([[{ 'name' => name, 'esc_period' => '3h', 'actionid' => id.to_s }]])
    end

    it 'creates the payload untouched when no action carries the name, and issues no update' do
      created = Fixtures.exchange('actions/crud', 'action.create', 11)
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.get', 14), created])
      unseen = "#{name}-unseen"

      expect(described_class.new(fake).create_or_update(name: unseen, eventsource: 0, status: 1)).to eq(created['result']['actionids'].first.to_i)
      expect(fake.sent('action.create')).to eq([[{ 'name' => unseen, 'eventsource' => 0, 'status' => 1 }]])
      expect(fake.count('action.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.get', 15)])

      expect(described_class.new(fake).get_or_create(name: name, eventsource: 0, status: 1)).to eq(id)
      expect(fake.count('action.create')).to eq(0)
    end

    it 'looks the name up alone and creates the whole payload when nothing matches' do
      created = Fixtures.exchange('actions/crud', 'action.create', 12)
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.get', 16), created])
      unseen = "#{name}-unknown"

      expect(described_class.new(fake).get_or_create(name: unseen, eventsource: 0, status: 1, esc_period: '1h')).to eq(created['result']['actionids'].first.to_i)
      expect(fake.sent('action.get')).to eq([{ 'filter' => { 'name' => unseen }, 'output' => %w[actionid name] }])
      expect(fake.sent('action.create')).to eq([[{ 'name' => unseen, 'eventsource' => 0, 'status' => 1, 'esc_period' => '1h' }]])
    end
  end

  describe 'a refusal the server sent back' do
    it "reaches the caller as an ApiError whose error_message joins the server's message and data" do
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.create', 1)])

      expect { described_class.new(fake).create(name: name, eventsource: 0, status: 1) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/\AInvalid params\.: Action .* already exists\.\z/) }
    end

    it 'reaches the caller from the second request too, the dump before it having succeeded' do
      fake = FakeClient.new([Fixtures.exchange('actions/crud', 'action.get', 11), Fixtures.exchange('actions/crud', 'action.update', 2)])

      expect { described_class.new(fake).update(actionid: id, eventsource: 1) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/Cannot update .eventsource. for action/) }
      expect(fake.count('action.get')).to eq(1)
    end
  end
end
