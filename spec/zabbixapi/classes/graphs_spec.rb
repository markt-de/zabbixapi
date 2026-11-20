# Contract: ZabbixApi::Graphs
#   evidence: spec/fixtures/graphs/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/graph,
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/graphitem
#   classes:  hooks, no default_options | create wraps one object and merges nothing | get_full_data
#             searches where every other class filters, and drops the search rather than sending a
#             null name | get_raw and dump_by_id, and what each sends | get_id refuses when one name
#             sits on two hosts, and is exact when the caller scopes | all collapses those names to
#             a single Integer id | get_ids_by_host filters on host, hands back Integers and narrows
#             them client-side with a Ruby regexp | get_items sends graphitem.get for a bare id and
#             wraps whatever it is given | update skips equal, issues differing, force, never skips
#             gitems, refuses without an id | the two upserts: lookup by name plus hostid,
#             strip_scope off either branch, the Integer id merged into the write | aliases | delete
#             sends a bare id and returns an Integer, both recorded answers holding a String | six
#             server refusals through error_message
#   not here: all against a recording - graph.get with output: 'extend' and no filter returns every
#             graph on the server, so the shared group drives it from recorded rows; the substring
#             semantics of get_full_data itself, which only a server can show; enum values outside
#             their documented ranges or reserved for pie and exploded graphs, and the width and
#             height the server defaults although the reference requires them - server validation of
#             values the gem forwards untouched, pending in the acceptance spec; the select options
#             and further get parameters, which get_raw passes through, one representative kept; a
#             graph on a template, the copy a link inherits and the item cascade, server behaviour
#             the acceptance spec reads back - the upsert puts the identical request on the wire for
#             a template id and a host id; bulk arrays, which Basic#create and #delete handle and
#             Basic's own spec covers
require 'spec_helper'

RSpec.describe ZabbixApi::Graphs do
  crud = Fixtures.exchanges('graphs/crud')

  created = Fixtures.exchange('graphs/crud', 'graph.create')
  refused_gitems = Fixtures.exchange('graphs/crud', 'graph.create', 3)
  refused_color = Fixtures.exchange('graphs/crud', 'graph.create', 4)
  refused_duplicate = Fixtures.exchange('graphs/crud', 'graph.create', 5)
  refused_templateid = Fixtures.exchange('graphs/crud', 'graph.create', 6)
  upsert_created = Fixtures.exchange('graphs/crud', 'graph.create', 7)
  goc_created = Fixtures.exchange('graphs/crud', 'graph.create', 8)

  searched = Fixtures.exchange('graphs/crud', 'graph.get')
  spanning = Fixtures.exchange('graphs/crud', 'graph.get', 1)
  both_hosts = Fixtures.exchange('graphs/crud', 'graph.get', 2)
  one_host = Fixtures.exchange('graphs/crud', 'graph.get', 3)
  dump = Fixtures.exchange('graphs/crud', 'graph.get', 5)
  by_host = Fixtures.exchange('graphs/crud', 'graph.get', 7)
  issued_dump = Fixtures.exchange('graphs/crud', 'graph.get', 9)
  skipped_dump = Fixtures.exchange('graphs/crud', 'graph.get', 10)
  readonly_dump = Fixtures.exchange('graphs/crud', 'graph.get', 13)
  upsert_lookup = Fixtures.exchange('graphs/crud', 'graph.get', 14)
  upsert_dump = Fixtures.exchange('graphs/crud', 'graph.get', 15)
  upsert_absent = Fixtures.exchange('graphs/crud', 'graph.get', 16)
  goc_absent = Fixtures.exchange('graphs/crud', 'graph.get', 18)

  issued_update = Fixtures.exchange('graphs/crud', 'graph.update')
  refused_readonly = Fixtures.exchange('graphs/crud', 'graph.update', 3)
  upsert_update = Fixtures.exchange('graphs/crud', 'graph.update', 4)

  deleted_by_integer = Fixtures.exchange('graphs/crud', 'graph.delete')
  deleted_by_string = Fixtures.exchange('graphs/crud', 'graph.delete', 1)
  refused_delete = Fixtures.exchange('graphs/crud', 'graph.delete', 2)

  gitems = Fixtures.exchange('graphs/crud', 'graphitem.get')
  refused_gitem_read = Fixtures.exchange('graphs/crud', 'graphitem.get', 1)

  row = dump['result'].first
  id = row['graphid'].to_i
  name = row['name']
  full_id = gitems['result'].first['graphid'].to_i
  itemid = gitems['result'].first['itemid'].to_i
  twin_id = both_hosts['result'].last['graphid'].to_i
  # The host the fixture was recorded against, under its technical name and its id. graph.get
  # returns neither, so neither can come from a row; the fake replays by method, so both only have
  # to be the values the example itself asserts on.
  host = 'zbxapi-spec-graphs-h1'
  hostid = 11101

  let(:client) { FakeClient.new(crud) }
  let(:graphs) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'graph', identify: 'name', key: 'graphid', keys: 'graphids', default_options: {}

  it_behaves_like 'an inherited create', payload: { name: name, width: 900, height: 200, gitems: [{ itemid: itemid, color: '00AA00' }] }, defaults: {}, exchange: created
  it_behaves_like 'an inherited delete', id: deleted_by_integer['result']['graphids'].first.to_i, exchange: deleted_by_integer
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'graphid', value: name, rows: one_host['result']
  it_behaves_like 'an inherited all', identify: 'name', key: 'graphid', rows: spanning['result']
  # get_full_data is overridden and gets its own examples below.
  it_behaves_like 'the inherited reads', identify: 'name', key: 'graphid', value: name, id: id, rows: [row], except: [:get_full_data]

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'graphid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_ids_by_host, field: 'host'

  # No output: 'extend' read returns gitems, so a payload naming them can never be proven equal to
  # the dump and the update has to be issued.
  it_behaves_like 'an update that skips when unchanged',
                  key: 'graphid', id: id, dump: [skipped_dump['result'].first],
                  unchanged: { height: 250 }, changed: { height: 300 },
                  collection: { gitems: [{ itemid: itemid, color: 'FFAA00' }] }

  # A graph name is unique per host only, so both upserts look up by name and hostid. Neither may
  # let the scope reach the write: graph.create and graph.update have no hostid parameter at all,
  # which is why strip_on_create is true here where Items keeps it.
  it_behaves_like 'a host-scoped upsert',
                  identify: 'name', key: 'graphid', hostid: hostid,
                  payload: { name: name, hostid: hostid, width: 950, gitems: [{ itemid: itemid, color: '00AA00' }] },
                  found: upsert_lookup['result'],
                  update_result: upsert_update['result'],
                  create_result: upsert_created['result'],
                  strip_on_create: true

  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name }, id: id

  # One instance per normalisation path: the plain symbolize_keys of the overridden get_full_data,
  # which stands in for create because the class has no default_options, the conditional one in
  # get_id, require_field! in dump_by_id and in get_ids_by_host, the dump comparison in update, and
  # the two overridden upserts, which build their lookup hash themselves.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: [searched]
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name, hostid: hostid }, exchanges: [one_host]
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { graphid: id }, exchanges: [dump]
  it_behaves_like 'a key-normalising entry point', method: :get_ids_by_host, payload: { host: host, filter: 'base\z' }, exchanges: [by_host]
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { graphid: id, height: 250 }, exchanges: [issued_dump, issued_update]
  it_behaves_like 'a key-normalising entry point', method: :get_or_create, payload: { name: name, hostid: hostid }, exchanges: [upsert_lookup]
  it_behaves_like 'a key-normalising entry point', method: :create_or_update, payload: { name: name, hostid: hostid, width: 950, gitems: [{ itemid: itemid, color: '00AA00' }] }, exchanges: [upsert_lookup, upsert_dump, upsert_update]

  describe '#get_full_data' do
    it 'searches rather than filters on the name, and asks for extend' do
      fake = FakeClient.new([searched])

      expect(described_class.new(fake).get_full_data(name: name)).to eq(searched['result'])
      expect(fake.sent('graph.get')).to eq([{ 'search' => { 'name' => name }, 'output' => 'extend' }])
    end

    it 'drops the search entirely rather than sending a null name' do
      fake = FakeClient.new([spanning])

      described_class.new(fake).get_full_data({})
      expect(fake.sent('graph.get')).to eq([{ 'output' => 'extend' }])
    end
  end

  describe '#get_id' do
    it 'without a hostid refuses, reporting two matches and their ids' do
      fake = FakeClient.new([both_hosts])

      expect(both_hosts['result'].size).to eq(2)
      ids = both_hosts['result'].map { |graph| graph['graphid'] }.uniq
      expect { described_class.new(fake).get_id(name: name) }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 graph objects, not one \(graphid #{ids.join(', ')}\): narrow the lookup\z/)
    end

    it 'with a hostid filters on name and hostid and returns the one id' do
      fake = FakeClient.new([one_host])

      expect(described_class.new(fake).get_id(name: name, hostid: hostid)).to eq(id)
      expect(fake.sent('graph.get').first['filter']).to eq('name' => name, 'hostid' => hostid)
    end
  end

  describe '#all' do
    it 'collapses the two graphs of one name into a single entry, the id an Integer' do
      fake = FakeClient.new([spanning])
      table = described_class.new(fake).all

      expect(spanning['result'].size).to eq(3)
      expect(table.size).to eq(2)
      expect(table[name]).to eq(twin_id)
    end
  end

  describe '#get_ids_by_host' do
    it 'filters on the technical host name, asks for extend and returns the ids as Integers' do
      fake = FakeClient.new([by_host])

      expect(described_class.new(fake).get_ids_by_host(host: host)).to eq(by_host['result'].map { |graph| graph['graphid'].to_i })
      expect(fake.sent('graph.get')).to eq([{ 'filter' => { 'host' => host }, 'output' => 'extend' }])
    end

    it 'narrows the answer with a Ruby regexp over the names, sending the very same request' do
      fake = FakeClient.new([by_host])

      expect(described_class.new(fake).get_ids_by_host(host: host, filter: 'base\z')).to eq([id])
      expect(fake.sent('graph.get')).to eq([{ 'filter' => { 'host' => host }, 'output' => 'extend' }])
    end

    it 'returns an empty Array when that regexp matches no name' do
      fake = FakeClient.new([by_host])

      expect(described_class.new(fake).get_ids_by_host(host: host, filter: 'no-such-graph')).to eq([])
    end
  end

  describe '#get_items' do
    it 'sends graphitem.get for the bare graph id, wrapped in an Array, and returns the graph items' do
      fake = FakeClient.new([gitems])
      found = described_class.new(fake).get_items(full_id)

      expect(fake.sent('graphitem.get')).to eq([{ 'graphids' => [full_id], 'output' => 'extend' }])
      expect(found).to eq(gitems['result'])
      expect(found.first.keys).to include('gitemid', 'itemid', 'color')
    end

    it 'wraps whatever it is given, so a Hash goes out as a graph id and is refused' do
      fake = FakeClient.new([refused_gitem_read])

      expect { described_class.new(fake).get_items(graphids: full_id) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/Database error occurred/) }
      expect(fake.sent('graphitem.get')).to eq([{ 'graphids' => [{ 'graphids' => full_id }], 'output' => 'extend' }])
    end
  end

  describe '#strip_scope' do
    it 'drops hostid and templateid and keeps every other field' do
      scoped = { name: name, hostid: hostid, templateid: 999999, width: 950, gitems: [] }

      expect(graphs.strip_scope(scoped)).to eq(name: name, width: 950, gitems: [])
    end
  end

  describe '#update' do
    it 'raises before any request when the payload names no graphid' do
      expect { graphs.update(height: 250) }.to raise_error(ZabbixApi::ApiError, /graphid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end
  end

  describe '#create_or_update' do
    it 'looks up by name and hostid alone, then writes the found id as an Integer and neither scoping field' do
      fake = FakeClient.new([upsert_lookup, upsert_dump, upsert_update])

      expect(described_class.new(fake).create_or_update(name: name, hostid: hostid, templateid: 999999, width: 950, gitems: [{ itemid: itemid, color: '00AA00' }]))
        .to eq(id)
      expect(fake.sent('graph.get').first).to eq('filter' => { 'name' => name, 'hostid' => hostid }, 'output' => %w[graphid name])
      expect(fake.sent('graph.update')).to eq([[{ 'name' => name, 'width' => 950, 'gitems' => [{ 'itemid' => itemid, 'color' => '00AA00' }], 'graphid' => id }]])
    end

    it 'creates without the scoping fields when that host carries no graph of the name' do
      fake = FakeClient.new([upsert_absent, upsert_created])
      fresh = "#{name}-cou"

      expect(described_class.new(fake).create_or_update(name: fresh, hostid: hostid, templateid: 999999, width: 900, height: 200, gitems: [{ itemid: itemid, color: '00AA00' }]))
        .to eq(upsert_created['result']['graphids'].first.to_i)
      expect(fake.sent('graph.create')).to eq([[{ 'name' => fresh, 'width' => 900, 'height' => 200, 'gitems' => [{ 'itemid' => itemid, 'color' => '00AA00' }] }]])
      expect(fake.count('graph.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'drops a hostid the caller never gave instead of filtering on null, then refuses what that leaves' do
      fake = FakeClient.new([both_hosts])
      ids = both_hosts['result'].map { |graph| graph['graphid'] }.uniq

      expect { described_class.new(fake).get_or_create(name: name) }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched #{ids.size} graph objects, not one \(graphid #{ids.join(', ')}\): narrow the lookup\z/)
      expect(fake.sent('graph.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => %w[graphid name] }])
      expect(fake.count('graph.create')).to eq(0)
    end

    it 'creates without the scoping fields when the lookup finds nothing' do
      fake = FakeClient.new([goc_absent, goc_created])
      fresh = "#{name}-goc"

      expect(described_class.new(fake).get_or_create(name: fresh, hostid: hostid, templateid: 999999, width: 900, height: 200, gitems: [{ itemid: itemid, color: '3333FF' }]))
        .to eq(goc_created['result']['graphids'].first.to_i)
      expect(fake.sent('graph.create')).to eq([[{ 'name' => fresh, 'width' => 900, 'height' => 200, 'gitems' => [{ 'itemid' => itemid, 'color' => '3333FF' }] }]])
    end
  end

  describe '#delete' do
    it 'sends the bare id and returns an Integer, both recorded answers holding a String' do
      integer_id = deleted_by_integer['result']['graphids'].first
      string_id = deleted_by_string['result']['graphids'].first
      expect([integer_id, string_id]).to match([an_instance_of(String), an_instance_of(String)])

      by_integer = FakeClient.new([deleted_by_integer])
      by_string = FakeClient.new([deleted_by_string])
      expect(described_class.new(by_integer).delete(integer_id.to_i)).to eq(integer_id.to_i)
      expect(described_class.new(by_string).delete(string_id)).to eq(string_id.to_i)
      expect([by_integer.sent('graph.delete'), by_string.sent('graph.delete')]).to eq([[[integer_id.to_i]], [[string_id]]])
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create, update and delete' do
      minimal = { name: name, width: 900, height: 200, gitems: [{ itemid: itemid, color: '00AA00' }] }
      [
        [refused_gitems, ->(wrapper) { wrapper.create(minimal.reject { |field, _| field == :gitems }) }, /Missing items for graph/],
        [refused_color, ->(wrapper) { wrapper.create(minimal.merge(gitems: [{ itemid: itemid, color: 'not-a-colour' }])) }, /expecting hexadecimal color code/],
        [refused_duplicate, ->(wrapper) { wrapper.create(minimal) }, /already exists on the host/],
        [refused_templateid, ->(wrapper) { wrapper.create(minimal.merge(templateid: 999999)) }, /Cannot set "templateid"/],
        [refused_readonly, ->(wrapper) { wrapper.update(graphid: id, templateid: 999999) }, /Cannot update "templateid"/],
        [refused_delete, ->(wrapper) { wrapper.delete(999999999) }, /does not exist/]
      ].each do |exchange, call, reason|
        exchanges = exchange['method'] == 'graph.update' ? [readonly_dump, exchange] : [exchange]
        wrapper = described_class.new(FakeClient.new(exchanges))
        expect { call.call(wrapper) }.to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
