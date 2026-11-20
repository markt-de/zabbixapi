# Contract: ZabbixApi::Items
#   evidence: spec/fixtures/items/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/item
#   classes:  hooks and ZERO_DELAY_TYPES | create merges the eighteen defaults under the caller and
#             wraps one object | delay 0 for a zero-delay type, decided on type.to_i, never over an
#             explicit delay | an unset nil default is dropped, never nulled | the four reads and
#             what each sends | get_id refuses when a name repeats across hosts, and narrows to one
#             host when scoped | all collapses those names to one Integer id | update skips equal,
#             issues differing, force, never skips a collection, refuses without an id | the two
#             upsert overrides: the lookup is name plus hostid with a nil hostid dropped, the update
#             strips hostid and merges an Integer itemid | aliases | delete sends a bare id and
#             returns an Integer whether the answer holds an Integer or a String | four server
#             refusals through error_message
#   not here: all against a recording - output: 'extend' with no filter returns every item on the
#             server, so the shared group drives it from scripted rows; the eighteen types and the
#             four interface kinds, the value_type matrix against trends and binary on a dependent
#             item - server validation of fields the gem only forwards, one refused representative
#             kept here and accepted representatives proven live; the delete cascade onto a
#             dependent item and the inherited copy, which are server behaviour and belong live; web
#             items, which need a web scenario to exist at all; flags, never written anywhere:
#             item.create accepts 4 but stores 0, and item.update refuses it as an unexpected
#             parameter; bulk arrays, which Basic#create and #delete handle and Basic's own spec
#             covers, Items#create correcting each object's delay first, a step no spec runs on an
#             Array; the server's answer to an omitted key_, which the acceptance spec pins live
require 'spec_helper'

RSpec.describe ZabbixApi::Items do
  # Spelled out rather than taken from Items#default_options, so a changed default fails here.
  defaults = {
    name: nil, key_: nil, hostid: nil, delay: '60', status: 0, type: 7, snmp_oid: '',
    value_type: 3, units: '', logtimefmt: '', valuemapid: 0, authtype: 0, username: '',
    password: '', publickey: '', privatekey: '', params: '', ipmi_sensor: ''
  }

  created = Fixtures.exchange('items/crud', 'item.create')
  trapper = Fixtures.exchange('items/crud', 'item.create', 1)
  dependent = Fixtures.exchange('items/crud', 'item.create', 2)
  refused_delay = Fixtures.exchange('items/crud', 'item.create', 3)
  refused_key = Fixtures.exchange('items/crud', 'item.create', 4)
  refused_duplicate = Fixtures.exchange('items/crud', 'item.create', 5)
  refused_type = Fixtures.exchange('items/crud', 'item.create', 6)
  upsert_created = Fixtures.exchange('items/crud', 'item.create', 8)

  spanning = Fixtures.exchange('items/crud', 'item.get')
  both_hosts = Fixtures.exchange('items/crud', 'item.get', 1)
  one_host = Fixtures.exchange('items/crud', 'item.get', 2)
  dump = Fixtures.exchange('items/crud', 'item.get', 4)
  issued_dump = Fixtures.exchange('items/crud', 'item.get', 6)
  hostid_dump = Fixtures.exchange('items/crud', 'item.get', 10)
  readonly_dump = Fixtures.exchange('items/crud', 'item.get', 11)
  upsert_lookup = Fixtures.exchange('items/crud', 'item.get', 12)
  upsert_dump = Fixtures.exchange('items/crud', 'item.get', 13)
  upsert_absent = Fixtures.exchange('items/crud', 'item.get', 14)
  scoped_lookup = Fixtures.exchange('items/crud', 'item.get', 17)

  issued_update = Fixtures.exchange('items/crud', 'item.update')
  refused_hostid = Fixtures.exchange('items/crud', 'item.update', 3)
  refused_readonly = Fixtures.exchange('items/crud', 'item.update', 4)
  upsert_update = Fixtures.exchange('items/crud', 'item.update', 5)

  deleted_by_integer = Fixtures.exchange('items/crud', 'item.delete')
  deleted_by_string = Fixtures.exchange('items/crud', 'item.delete', 1)
  refused_delete = Fixtures.exchange('items/crud', 'item.delete', 2)

  row = dump['result'].first
  id = row['itemid'].to_i
  name = row['name']
  key = row['key_']
  hostid = row['hostid'].to_i
  twin_id = both_hosts['result'].last['itemid'].to_i

  let(:client) { FakeClient.new(Fixtures.exchanges('items/crud')) }
  let(:items) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'item', identify: 'name', key: 'itemid', keys: 'itemids', default_options: defaults

  # create, get_or_create and create_or_update are overridden and get their own examples below.
  it_behaves_like 'an inherited delete', id: deleted_by_integer['result']['itemids'].first, exchange: deleted_by_integer
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'itemid', value: name, rows: one_host['result']
  it_behaves_like 'an inherited all', identify: 'name', key: 'itemid', rows: both_hosts['result']
  it_behaves_like 'the inherited reads', identify: 'name', key: 'itemid', value: name, id: id, rows: spanning['result']
  it_behaves_like 'the aliases', exchanges: [spanning, created, deleted_by_integer], payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'itemid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # tags are stored and never returned by output: 'extend', so a payload naming them can never be
  # proven equal and the update has to be issued.
  it_behaves_like 'an update that skips when unchanged',
                  key: 'itemid', id: id, dump: [row],
                  unchanged: { name: name }, changed: { name: "#{name}-renamed" },
                  collection: { tags: [{ tag: 'zbxapi-spec', value: 'items' }] }

  # hostid scopes both upserts' lookup to one host, where an item name can repeat under another key,
  # and must stay out of the write: item.update refuses it as an unexpected parameter and an item
  # cannot move hosts anyway. item.create requires it, so the create branch keeps it.
  it_behaves_like 'a host-scoped upsert',
                  identify: 'name', key: 'itemid', hostid: hostid,
                  payload: { name: name, key_: key, hostid: hostid, description: 'upserted' },
                  found: upsert_lookup['result'],
                  update_result: upsert_update['result'],
                  create_result: upsert_created['result'],
                  strip_on_create: false

  # One instance per normalisation path: the defaults merge in create, the conditional symbolize in
  # get_id, require_field! in dump_by_id, the dump comparison in update, and the two overridden
  # upserts, which build their lookup hash themselves.
  it_behaves_like 'a key-normalising entry point', method: :create, payload: { name: name, key_: key, hostid: hostid }, exchanges: [created]
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name, hostid: hostid }, exchanges: [one_host]
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { itemid: id }, exchanges: [dump]
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { itemid: id, description: 'spec one' }, exchanges: [issued_dump, issued_update]
  it_behaves_like 'a key-normalising entry point', method: :get_or_create, payload: { name: name, hostid: hostid }, exchanges: [upsert_lookup]
  it_behaves_like 'a key-normalising entry point', method: :create_or_update, payload: { name: name, key_: key, hostid: hostid, description: 'upserted' }, exchanges: [upsert_lookup, upsert_dump, upsert_update]

  describe 'ZERO_DELAY_TYPES' do
    it 'names Zabbix trapper, SNMP trap and dependent' do
      expect(ZabbixApi::Items::ZERO_DELAY_TYPES).to eq([2, 17, 18])
    end
  end

  describe '#create' do
    it 'merges the eighteen defaults under the caller and sends one object inside an Array' do
      fake = FakeClient.new([created])
      expected = JSON.parse(JSON.generate(defaults.merge(name: name, key_: key, hostid: hostid)))

      expect(described_class.new(fake).create(name: name, key_: key, hostid: hostid)).to eq(created['result']['itemids'].first.to_i)
      expect(fake.sent('item.create')).to eq([[expected]])
      expect(expected.keys.size).to eq(18)
    end

    it 'supplies delay 0 for a zero-delay type the caller gave no delay for, and changes nothing else' do
      fake = FakeClient.new([trapper])
      described_class.new(fake).create(name: name, key_: key, hostid: hostid, type: 2)

      sent = fake.sent('item.create').first.first
      expect(sent['delay']).to eq(0)
      expect(sent).to eq(JSON.parse(JSON.generate(defaults.merge(name: name, key_: key, hostid: hostid, type: 2, delay: 0))))
    end

    it 'supplies delay 0 for a zero-delay type given as a String, and forwards the String unchanged' do
      fake = FakeClient.new([dependent])
      described_class.new(fake).create(name: name, key_: key, hostid: hostid, type: '18', master_itemid: id)

      expect(fake.sent('item.create').first.first).to include('type' => '18', 'delay' => 0, 'master_itemid' => id)
    end

    it 'leaves the default alone for a type outside ZERO_DELAY_TYPES' do
      fake = FakeClient.new([created])
      described_class.new(fake).create(name: name, key_: key, hostid: hostid, type: 0)

      expect(fake.sent('item.create').first.first['delay']).to eq('60')
    end

    it 'forwards a delay the caller passed untouched, even where the server demands 0 for that type' do
      fake = FakeClient.new([refused_delay])

      expect { described_class.new(fake).create(name: name, key_: key, hostid: hostid, type: 2, delay: '1m') }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(%r{/1/delay.*value must be 0}) }
      expect(fake.sent('item.create').first.first['delay']).to eq('1m')
    end

    it 'omits a default the caller did not fill rather than sending it as an explicit null' do
      fake = FakeClient.new([refused_key])

      expect { described_class.new(fake).create(name: name, hostid: hostid) }.to raise_error(ZabbixApi::ApiError)
      expect(fake.sent('item.create').first.first).not_to have_key('key_')
    end
  end

  describe '#get_id' do
    it 'refuses two matches of one name, naming both ids, when nothing but the name filters' do
      fake = FakeClient.new([both_hosts])
      ids = both_hosts['result'].map { |item| item['itemid'] }.uniq

      expect { described_class.new(fake).get_id(name: name) }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched #{ids.size} item objects, not one \(itemid #{ids.join(', ')}\): narrow the lookup\z/)
      expect(fake.sent('item.get').first).to eq('filter' => { 'name' => name }, 'output' => %w[itemid name])
    end

    it 'narrows the lookup to that host when the caller adds a hostid, because the whole hash filters' do
      fake = FakeClient.new([one_host])

      expect(described_class.new(fake).get_id(name: name, hostid: hostid)).to eq(id)
      expect(fake.sent('item.get').first['filter']).to eq('name' => name, 'hostid' => hostid)
    end
  end

  describe '#all' do
    it 'collapses two items of one name into a single entry, the id an Integer' do
      fake = FakeClient.new([both_hosts])
      table = described_class.new(fake).all

      expect(both_hosts['result'].size).to eq(2)
      expect(table.size).to eq(1)
      expect(table[name]).to eq(twin_id)
    end
  end

  describe '#update' do
    it 'raises before any request when the payload names no itemid' do
      expect { items.update(description: 'spec one') }.to raise_error(ZabbixApi::ApiError, /itemid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end

    it 'forwards a hostid the caller supplied, which the server refuses as an unexpected parameter' do
      fake = FakeClient.new([hostid_dump, refused_hostid])

      expect { described_class.new(fake).update(itemid: id, hostid: hostid, description: 'hostid must not reach the update') }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/unexpected parameter "hostid"/) }
      expect(fake.sent('item.update').first.first).to include('hostid' => hostid)
    end
  end

  describe '#create_or_update' do
    it 'looks up by name and hostid only, then updates with the found id as an Integer and no hostid' do
      fake = FakeClient.new([upsert_lookup, upsert_dump, upsert_update])

      expect(described_class.new(fake).create_or_update(name: name, key_: key, hostid: hostid, description: 'upserted')).to eq(id)
      expect(fake.sent('item.get').first).to eq('filter' => { 'name' => name, 'hostid' => hostid }, 'output' => %w[itemid name])
      expect(fake.sent('item.update')).to eq([[{ 'name' => name, 'key_' => key, 'description' => 'upserted', 'itemid' => id }]])
    end

    it 'creates with the hostid the caller gave when nothing of that name exists on that host' do
      fake = FakeClient.new([upsert_absent, upsert_created])
      fresh = "#{name}-cou"

      expect(described_class.new(fake).create_or_update(name: fresh, key_: key, hostid: hostid)).to eq(upsert_created['result']['itemids'].first.to_i)
      expect(fake.sent('item.create').first.first).to include('name' => fresh, 'hostid' => hostid)
      expect(fake.count('item.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'drops a hostid the caller never gave instead of filtering on null' do
      fake = FakeClient.new([one_host])

      expect(described_class.new(fake).get_or_create(name: name)).to eq(id)
      expect(fake.sent('item.get').first).to eq('filter' => { 'name' => name }, 'output' => %w[itemid name])
    end

    it 'resolves the same name to the other host when the caller scopes it there' do
      fake = FakeClient.new([scoped_lookup])
      other_hostid = hostid + 1

      expect(described_class.new(fake).get_or_create(name: name, hostid: other_hostid)).to eq(twin_id)
      expect(fake.sent('item.get').first['filter']).to eq('name' => name, 'hostid' => other_hostid)
    end
  end

  describe '#delete' do
    it 'sends the bare id and returns an Integer, whether the answer holds an Integer or a String' do
      echoed_integer = deleted_by_integer['result']['itemids'].first
      echoed_string = deleted_by_string['result']['itemids'].first
      expect([echoed_integer, echoed_string]).to match([an_instance_of(Integer), an_instance_of(String)])

      by_integer = FakeClient.new([deleted_by_integer])
      by_string = FakeClient.new([deleted_by_string])
      expect(described_class.new(by_integer).delete(echoed_integer)).to eq(echoed_integer)
      expect(described_class.new(by_string).delete(echoed_string)).to eq(echoed_string.to_i)
      expect([by_integer.sent('item.delete'), by_string.sent('item.delete')]).to eq([[[echoed_integer]], [[echoed_string]]])
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create, update and delete' do
      [
        [refused_duplicate, ->(wrapper) { wrapper.create(name: name, key_: key, hostid: hostid) }, /already exists on the host/],
        [refused_type, ->(wrapper) { wrapper.create(name: name, key_: key, hostid: hostid, type: 9, delay: '1m') }, %r{/1/type.*value must be one of}],
        [refused_readonly, ->(wrapper) { wrapper.update(itemid: id, templateid: 999999) }, /unexpected parameter "templateid"/],
        [refused_delete, ->(wrapper) { wrapper.delete(999999999) }, /does not exist/]
      ].each do |exchange, call, reason|
        exchanges = exchange['method'] == 'item.update' ? [readonly_dump, exchange] : [exchange]
        wrapper = described_class.new(FakeClient.new(exchanges))
        expect { call.call(wrapper) }.to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
