# Contract: ZabbixApi::ValueMaps
#   evidence: spec/fixtures/valuemaps/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/valuemap
#   classes:  hooks, key and keys derived | create wraps one object and merges no defaults | the
#             four reads and the request each builds | get_id filters on the whole payload, so the
#             hostid scope is what makes a repeated name exact and the unscoped lookup is refused |
#             all collapses the repeated name | update skips an equal payload, issues a differing
#             one, issues a mappings payload the dump cannot show, honours force, refuses without an
#             id, and carries a constant hostid to the server that refuses it | the two overridden
#             upserts: the scoped lookup, the stripped hostid, the Integer id merged in, the create
#             branch keeping hostid, the unscoped fallback when no hostid is given | the three
#             aliases | delete sends a bare id and returns an Integer, both recorded answers holding
#             a String | key normalisation, six entry points | refusals: a missing required
#             property, a type 5 mapping carrying a value, an unknown id
#   not here: `all` against the real table, which holds every value map on the server, so the shared
#             group builds it from two recorded rows; the uuid and mapping-type refusals, server
#             validation the acceptance spec asserts; bulk arrays, which Basic#create and #delete
#             handle and Basic's own spec covers; the user type create, update and delete require,
#             which needs a second user: an Admin user with read-write on the host's group may call
#             all three, though their references name Super admin alone; whether a template value
#             map is copied to a linked host, which no offline replay can show
require 'spec_helper'

RSpec.describe ZabbixApi::ValueMaps do
  crud = Fixtures.exchanges('valuemaps/crud')
  # The two hosts carry one name between them, which is what makes this class's scope necessary.
  both = Fixtures.exchange('valuemaps/crud', 'valuemap.get')['result']
  row = Fixtures.exchange('valuemaps/crud', 'valuemap.get', 4)['result'].first
  scoped = Fixtures.exchange('valuemaps/crud', 'valuemap.get', 1)['result']
  id = row['valuemapid'].to_i
  name = row['name']
  hostid = row['hostid'].to_i
  eq = [{ type: 0, value: '1', newvalue: 'Up' }]
  two = [{ type: 0, value: '0', newvalue: 'Offline' }, { type: 0, value: '1', newvalue: 'Online' }]
  # The update branch of create_or_update: the scoped lookup, the dump Basic#update compares
  # against, and the update itself.
  upsert_update = [Fixtures.exchange('valuemaps/crud', 'valuemap.get', 14),
                   Fixtures.exchange('valuemaps/crud', 'valuemap.get', 15),
                   Fixtures.exchange('valuemaps/crud', 'valuemap.update', 4)]

  let(:client) { FakeClient.new(crud) }
  let(:valuemaps) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'valuemap', identify: 'name', key: 'valuemapid', keys: 'valuemapids', default_options: {}

  it_behaves_like 'an inherited create', payload: { hostid: hostid, name: name, mappings: eq }, defaults: {}, exchange: Fixtures.exchange('valuemaps/crud', 'valuemap.create')
  it_behaves_like 'an inherited delete', id: Fixtures.exchange('valuemaps/crud', 'valuemap.delete', 1)['params'].first, exchange: Fixtures.exchange('valuemaps/crud', 'valuemap.delete', 1)
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'valuemapid', value: name, rows: scoped
  it_behaves_like 'an inherited all', identify: 'name', key: 'valuemapid', rows: both
  it_behaves_like 'the inherited reads', identify: 'name', key: 'valuemapid', value: name, id: id, rows: [row]
  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'valuemapid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'
  # mappings are the collection output: extend never returns, so a payload carrying them is issued
  # however equal it looks.
  it_behaves_like 'an update that skips when unchanged', key: 'valuemapid', id: id, dump: [row], unchanged: { name: name }, changed: { name: "#{name}-renamed" }, collection: { mappings: two }
  it_behaves_like 'a host-scoped upsert', identify: 'name', key: 'valuemapid', hostid: hostid,
                                          payload: { name: name, hostid: hostid, mappings: eq },
                                          found: scoped,
                                          update_result: Fixtures.exchange('valuemaps/crud', 'valuemap.update', 4)['result'],
                                          create_result: Fixtures.exchange('valuemaps/crud', 'valuemap.create', 8)['result'],
                                          strip_on_create: false
  it_behaves_like 'the aliases', exchanges: crud, payload: { hostid: hostid, name: name, mappings: eq }, id: id

  # One instance per normalisation mechanism: the plain symbolize_keys of a filter-building read,
  # the conditional one in get_id, require_field! in dump_by_id, the dump comparison in update, and
  # the two overrides, which read :name and :hostid out of the caller's hash themselves. create
  # would be a seventh only for a class carrying default_options; without them its mechanism is
  # get_full_data's.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: [Fixtures.exchange('valuemaps/crud', 'valuemap.get')]
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name, hostid: hostid }, exchanges: [Fixtures.exchange('valuemaps/crud', 'valuemap.get', 1)]
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { valuemapid: id }, exchanges: [Fixtures.exchange('valuemaps/crud', 'valuemap.get', 4)]
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { valuemapid: id, name: "#{name}-renamed" }, exchanges: [Fixtures.exchange('valuemaps/crud', 'valuemap.get', 10), Fixtures.exchange('valuemaps/crud', 'valuemap.update')]
  it_behaves_like 'a key-normalising entry point', method: :get_or_create, payload: { hostid: hostid, name: name, mappings: eq }, exchanges: [Fixtures.exchange('valuemaps/crud', 'valuemap.get', 17)]
  it_behaves_like 'a key-normalising entry point', method: :create_or_update, payload: { hostid: hostid, name: name, mappings: eq }, exchanges: upsert_update

  describe '#get_id' do
    it 'refuses two rows sharing a name, where the hostid scope returns the one on that host' do
      unscoped = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.get', 2)])
      narrowed = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.get', 1)])
      ids = Fixtures.exchange('valuemaps/crud', 'valuemap.get', 2)['result'].map { |map| map['valuemapid'] }.uniq

      expect { described_class.new(unscoped).get_id(name: name) }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched #{ids.size} valuemap objects, not one \(valuemapid #{ids.join(', ')}\): narrow the lookup\z/)
      expect(described_class.new(narrowed).get_id(name: name, hostid: hostid)).to eq(id)
      expect(narrowed.sent('valuemap.get')).to eq([{ 'filter' => { 'name' => name, 'hostid' => hostid }, 'output' => %w[valuemapid name] }])
    end
  end

  describe '#all' do
    it 'collapses the two hosts of one name into a single entry, the last row winning' do
      table = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.get')])

      expect(described_class.new(table).all).to eq(name => both.last['valuemapid'].to_i)
    end
  end

  describe '#dump_by_id' do
    it "hands the server's rows back untouched, the Array of Hashes carrying the four properties extend answers with, two more than the valuemap.get reference's example shows" do
      fake = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.get', 4)])

      expect(described_class.new(fake).dump_by_id(valuemapid: id)).to eq([row])
      expect(row.keys).to contain_exactly('valuemapid', 'hostid', 'name', 'uuid')
    end
  end

  describe '#get_raw' do
    it 'passes the undocumented hostids parameter through unchanged and returns what came back' do
      fake = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.get', 7)])
      rows = Fixtures.exchange('valuemaps/crud', 'valuemap.get', 7)['result']

      expect(described_class.new(fake).get_raw(hostids: [hostid], output: %w[valuemapid name])).to eq(rows)
      expect(fake.sent('valuemap.get')).to eq([{ 'hostids' => [hostid], 'output' => %w[valuemapid name] }])
    end

    it 'returns the mappings under selectMappings extend and a String count under selectMappings count' do
      extended = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.get', 5)])
      counted = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.get', 6)])

      expect(described_class.new(extended).get_raw(valuemapids: [id], selectMappings: 'extend').first['mappings'])
        .to eq([{ 'value' => '1', 'newvalue' => 'Up', 'type' => '0' }])
      expect(described_class.new(counted).get_raw(valuemapids: [id], selectMappings: 'count').first['mappings']).to eq('1')
    end
  end

  describe '#update' do
    it 'raises before any request when the payload names no valuemapid' do
      expect { valuemaps.update(name: name) }.to raise_error(ZabbixApi::ApiError, /valuemapid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end

    it 'sends a hostid the caller left in the payload and lets the server refuse it as an unexpected parameter, the dump having gone out first' do
      fake = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.get', 13), Fixtures.exchange('valuemaps/crud', 'valuemap.update', 3)])

      expect { described_class.new(fake).update(valuemapid: id, hostid: hostid, name: "#{name}-moved") }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/unexpected parameter "hostid"/) }
      expect(fake.sent('valuemap.update')).to eq([[{ 'valuemapid' => id, 'hostid' => hostid, 'name' => "#{name}-moved" }]])
      expect(fake.count('valuemap.get')).to eq(1)
    end
  end

  describe '#get_or_create' do
    it 'looks the name up scoped by hostid, asking for the id and the name only, and creates nothing when it matches' do
      fake = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.get', 17)])

      expect(described_class.new(fake).get_or_create(hostid: hostid, name: name, mappings: eq)).to eq(id)
      expect(fake.sent('valuemap.get')).to eq([{ 'filter' => { 'name' => name, 'hostid' => hostid }, 'output' => %w[valuemapid name] }])
      expect(fake.count('valuemap.create')).to eq(0)
    end

    it 'creates the payload as given, hostid included' do
      lookup = Fixtures.exchange('valuemaps/crud', 'valuemap.get', 18)
      created = Fixtures.exchange('valuemaps/crud', 'valuemap.create', 9)
      fresh = created['params'].first['name']
      fake = FakeClient.new([lookup, created])

      expect(described_class.new(fake).get_or_create(hostid: hostid, name: fresh, mappings: eq)).to eq(created['result']['valuemapids'].first.to_i)
      expect(fake.sent('valuemap.create')).to eq([[{ 'hostid' => hostid, 'name' => fresh, 'mappings' => JSON.parse(JSON.generate(eq)) }]])
    end

    it 'drops a hostid it was never given rather than filtering on null, then refuses the span that leaves' do
      fake = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.get', 2)])
      ids = Fixtures.exchange('valuemaps/crud', 'valuemap.get', 2)['result'].map { |map| map['valuemapid'] }.uniq

      expect { described_class.new(fake).get_or_create(name: name, mappings: eq) }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched #{ids.size} valuemap objects, not one \(valuemapid #{ids.join(', ')}\): narrow the lookup\z/)
      expect(fake.sent('valuemap.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => %w[valuemapid name] }])
      expect(fake.count('valuemap.create')).to eq(0)
    end
  end

  describe '#create_or_update' do
    it 'updates with the id merged in as an Integer and without the constant hostid, the rest of the payload untouched' do
      fake = FakeClient.new(upsert_update)

      expect(described_class.new(fake).create_or_update(hostid: hostid, name: name, mappings: eq)).to eq(id)
      expect(fake.sent('valuemap.get')).to eq([{ 'filter' => { 'name' => name, 'hostid' => hostid }, 'output' => %w[valuemapid name] },
                                               { 'filter' => { 'valuemapid' => id }, 'output' => 'extend' }])
      expect(fake.sent('valuemap.update')).to eq([[{ 'name' => name, 'mappings' => JSON.parse(JSON.generate(eq)), 'valuemapid' => id }]])
      # Basic#create_or_update merges key => id.to_s; this override merges the Integer its get_id
      # returned.
      expect(fake.sent('valuemap.update').first.first['valuemapid']).to be_an(Integer)
    end

    it 'creates the payload as given when the host carries no map of that name, and issues no update' do
      lookup = Fixtures.exchange('valuemaps/crud', 'valuemap.get', 16)
      created = Fixtures.exchange('valuemaps/crud', 'valuemap.create', 8)
      fresh = created['params'].first['name']
      fake = FakeClient.new([lookup, created])

      expect(described_class.new(fake).create_or_update(hostid: hostid, name: fresh, mappings: eq)).to eq(created['result']['valuemapids'].first.to_i)
      expect(fake.sent('valuemap.create')).to eq([[{ 'hostid' => hostid, 'name' => fresh, 'mappings' => JSON.parse(JSON.generate(eq)) }]])
      expect(fake.count('valuemap.update')).to eq(0)
    end
  end

  describe '#delete' do
    it 'sends the bare id in an Array and returns an Integer, both recorded answers holding a String' do
      integer_id = Fixtures.exchange('valuemaps/crud', 'valuemap.delete', 1)
      string_id = Fixtures.exchange('valuemaps/crud', 'valuemap.delete', 2)
      # valuemap.delete does not echo the type it was given: both answers are Strings, so
      # parse_keys' to_i is what makes the return type uniform.
      expect([integer_id['result']['valuemapids'].first, string_id['result']['valuemapids'].first]).to all(be_a(String))

      by_number = FakeClient.new([integer_id])
      by_string = FakeClient.new([string_id])
      expect(described_class.new(by_number).delete(integer_id['params'].first)).to eq(integer_id['params'].first)
      expect(described_class.new(by_string).delete(string_id['params'].first)).to eq(string_id['params'].first.to_i)
      expect(by_string.sent('valuemap.delete')).to eq([[string_id['params'].first]])
    end
  end

  describe 'a refusal the server sent back' do
    it 'reaches the caller as an ApiError whose error_message names the missing property' do
      fake = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.create', 1)])

      expect { described_class.new(fake).create(hostid: hostid, name: "#{name}-nomap") }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/the parameter "mappings" is missing/) }
    end

    it 'carries the JSON pointer of the mapping the server rejected' do
      fake = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.create', 3)])

      expect { described_class.new(fake).create(hostid: hostid, name: "#{name}-ty5value", mappings: [{ type: 5, value: 'x', newvalue: 'y' }]) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(%r{/1/mappings/1/value.*should be empty}) }
    end

    it 'reaches the caller from a delete of an id no value map carries' do
      fake = FakeClient.new([Fixtures.exchange('valuemaps/crud', 'valuemap.delete', 3)])

      expect { described_class.new(fake).delete(999999999) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/No permissions to referred object or it does not exist/) }
    end
  end
end
