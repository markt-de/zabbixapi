# Contract: ZabbixApi::Templates
#   evidence: spec/fixtures/templates/crud.json, spec/fixtures/templates/mass.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/template
#   classes:  hooks | create wraps one object and merges no defaults | dump_by_id selects with
#             templateids and sends no filter at all | get_ids_by_host turns the host value into a
#             filter, passes any other template.get hash through untouched, and refuses its two
#             blind forms in different words | the inherited reads and what each sends | all maps
#             host to an Integer id | update skips what is equal, issues what differs, obeys force
#             and never skips a related collection | the four upsert branches, the update one
#             merging the id in as a String | the three aliases | delete sends a bare id and returns
#             an Integer | mass_add and mass_update build templates and groups objects where
#             mass_remove sends bare id arrays, each forwarding its own documented linking
#             parameters | mass_add and mass_remove refuse an unknown key and a payload without
#             templates_id | key normalisation, eight entry points | a server refusal carries its
#             reason into error_message
#   not here: bulk arrays, which Basic#create and #delete handle and Basic's own spec covers;
#             templategroup, which has its own class and specs; `all` over the real table, every
#             template on the server in a single exchange - one recorded row proves the mapping and
#             the live spec asserts membership; the server's side of the passthrough get parameters
#             and of every refusal, which is the live spec's
require 'spec_helper'

RSpec.describe ZabbixApi::Templates do
  crud = Fixtures.exchanges('templates/crud')
  mass = Fixtures.exchanges('templates/mass')
  row = Fixtures.exchange('templates/crud', 'template.get')['result'].first
  narrow = Fixtures.exchange('templates/crud', 'template.get', 1)['result']
  created = Fixtures.exchange('templates/crud', 'template.create')
  deleted = Fixtures.exchange('templates/crud', 'template.delete', 1)
  id = row['templateid'].to_i
  host = row['host']
  group = created['params'].first['groups'].first['groupid']
  macro = Fixtures.exchange('templates/mass', 'template.massAdd')['params']['macros'].first

  let(:client) { FakeClient.new(crud) }
  let(:templates) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'template', identify: 'host', key: 'templateid', keys: 'templateids', default_options: {}

  it_behaves_like 'an inherited create', payload: { host: host, groups: [{ groupid: group }] }, defaults: {}, exchange: created
  it_behaves_like 'an inherited delete', id: deleted['result']['templateids'].first.to_i, exchange: deleted
  it_behaves_like 'an inherited get_id', identify: 'host', key: 'templateid', value: host, rows: narrow
  it_behaves_like 'an inherited all', identify: 'host', key: 'templateid', rows: [row]
  # except: dump_by_id, which this class overrides; its own examples are below.
  it_behaves_like 'the inherited reads', identify: 'host', key: 'templateid', value: host, id: id, rows: [row], except: [:dump_by_id]
  it_behaves_like 'an update that skips when unchanged', key: 'templateid', id: id, dump: [row], unchanged: { host: host }, changed: { description: 'desc v1' }, collection: { macros: [macro] }
  it_behaves_like 'the aliases', exchanges: crud, payload: { host: host }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'templateid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'host'

  # One instance per normalisation path: three inherited entry points - get_full_data standing in
  # for create, which has no default_options to merge under - and the five entry points this class
  # defines itself, each of which reads the caller's keys on its own.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { host: host }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { host: host }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { templateid: id, description: 'desc v1' }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { templateid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_ids_by_host, payload: { host: host }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :mass_add, payload: { templates_id: [id], groups_id: [group] }, exchanges: mass
  it_behaves_like 'a key-normalising entry point', method: :mass_update, payload: { templates_id: [id], groups_id: [group] }, exchanges: mass
  it_behaves_like 'a key-normalising entry point', method: :mass_remove, payload: { templates_id: [id], groups_id: [group] }, exchanges: mass

  describe '#dump_by_id' do
    # Why the override exists - a filter on templateid matches nothing - is a server fact and is
    # asserted in the live spec; here only the request the override builds.
    it 'selects through the templateids parameter and sends no filter at all' do
      expect(templates.dump_by_id(templateid: id)).to eq([row])
      expect(client.sent('template.get').last).to eq('templateids' => [id], 'output' => 'extend')
    end
  end

  describe '#get_ids_by_host' do
    it 'turns the host value into a filter and asks for the id alone' do
      templates.get_ids_by_host(host: host)
      expect(client.sent('template.get').last).to eq('filter' => { 'host' => host }, 'output' => ['templateid'])
    end

    it 'returns the ids as Integers' do
      expect(templates.get_ids_by_host(host: host)).to eq([row['templateid'].to_i])
    end

    it 'passes a template.get parameter hash without host through untouched' do
      templates.get_ids_by_host(templateids: [id])
      expect(client.sent('template.get').last).to eq('templateids' => [id])
    end

    it 'refuses an empty hash before any request, naming the call' do
      expect { templates.get_ids_by_host({}) }.to raise_error(ZabbixApi::ApiError, /no parameters supplied in call to get_ids_by_host/)
      expect(client.calls).to be_empty
    end

    it 'refuses a nil host under a symbol key and under a string key' do
      expect { templates.get_ids_by_host(host: nil) }.to raise_error(ZabbixApi::ApiError, /host not supplied in call to get_ids_by_host/)
      expect { templates.get_ids_by_host('host' => nil) }.to raise_error(ZabbixApi::ApiError, /host not supplied in call to get_ids_by_host/)
      expect(client.calls).to be_empty
    end
  end

  describe '#mass_add' do
    let(:client) { FakeClient.new(mass) }

    it 'wraps the template and group ids into objects, forwards the macros as given, and reports true' do
      expect(templates.mass_add(templates_id: [id], groups_id: [group], macros: [macro])).to be(true)
      expect(client.sent('template.massAdd').last).to eq('templates' => [{ 'templateid' => id }], 'groups' => [{ 'groupid' => group }], 'macros' => [macro])
    end

    it 'maps templates_link_id into the objects massAdd wants' do
      expect(templates.mass_add(templates_id: [id], templates_link_id: [id])).to be(true)
      expect(client.sent('template.massAdd').last).to eq('templates' => [{ 'templateid' => id }], 'templates_link' => [{ 'templateid' => id }])
    end

    it 'refuses templates_clear_id and sends nothing, the template.massadd reference listing no templates_clear' do
      expect { templates.mass_add(templates_id: [id], templates_clear_id: [id]) }.to raise_error(ZabbixApi::ApiError, /unknown parameter templates_clear_id in call to mass_add/)
      expect(client.calls).to be_empty
    end

    it 'refuses a payload without templates_id before any request' do
      expect { templates.mass_add(groups_id: [group]) }.to raise_error(ZabbixApi::ApiError, /templates_id not supplied in call to mass_add/)
      expect(client.calls).to be_empty
    end

    it 'reports false when the server answers with an empty result' do
      empty = FakeClient.new([{ method: 'template.massAdd', result: {} }])
      expect(described_class.new(empty).mass_add(templates_id: [id])).to be(false)
    end
  end

  describe '#mass_update' do
    let(:client) { FakeClient.new(mass) }

    it 'wraps the template and group ids into objects, forwards the macros as given, and reports true' do
      expect(templates.mass_update(templates_id: [id], groups_id: [group], macros: [macro])).to be(true)
      expect(client.sent('template.massUpdate').last).to eq('templates' => [{ 'templateid' => id }], 'groups' => [{ 'groupid' => group }], 'macros' => [macro])
    end

    it 'maps templates_clear_id and templates_link_id into the objects massUpdate wants' do
      expect(templates.mass_update(templates_id: [id], templates_clear_id: [id], templates_link_id: [id])).to be(true)
      expect(client.sent('template.massUpdate').last).to eq('templates' => [{ 'templateid' => id }], 'templates_link' => [{ 'templateid' => id }], 'templates_clear' => [{ 'templateid' => id }])
    end
  end

  describe '#mass_remove' do
    let(:client) { FakeClient.new(mass) }

    it 'sends templates and groups as the bare id arrays the template.massremove reference documents, the macros as given, and reports true' do
      expect(templates.mass_remove(templates_id: [id], groups_id: [group], macros: [macro['macro']])).to be(true)
      expect(client.sent('template.massRemove').last).to eq('templateids' => [id], 'groupids' => [group], 'macros' => [macro['macro']])
    end

    it 'refuses the singular group_id and sends nothing' do
      expect { templates.mass_remove(templates_id: [id], group_id: group) }.to raise_error(ZabbixApi::ApiError, /unknown parameter group_id in call to mass_remove/)
      expect(client.calls).to be_empty
    end

    it 'sends the link parameters as the bare id arrays massRemove spells templateids_link and templateids_clear' do
      expect(templates.mass_remove(templates_id: [id], templates_link_id: [id], templates_clear_id: [id])).to be(true)
      expect(client.sent('template.massRemove').last).to eq('templateids' => [id], 'templateids_link' => [id], 'templateids_clear' => [id])
    end

    it 'refuses a payload without templates_id before any request' do
      expect { templates.mass_remove(groups_id: [group]) }.to raise_error(ZabbixApi::ApiError, /templates_id not supplied in call to mass_remove/)
      expect(client.calls).to be_empty
    end
  end

  describe '#create_or_update' do
    it 'looks the host up, dumps through templateids and updates with the id merged in as a String' do
      fake = FakeClient.new([Fixtures.exchange('templates/crud', 'template.get', 10), Fixtures.exchange('templates/crud', 'template.get', 11), Fixtures.exchange('templates/crud', 'template.update', 2)])

      expect(described_class.new(fake).create_or_update(host: host, description: 'via create_or_update')).to eq(id)
      expect(fake.sent('template.get')).to eq([{ 'filter' => { 'host' => host }, 'output' => %w[templateid host] }, { 'templateids' => [id.to_s], 'output' => 'extend' }])
      expect(fake.sent('template.update')).to eq([[{ 'host' => host, 'description' => 'via create_or_update', 'templateid' => id.to_s }]])
    end

    it 'creates without any id when no template carries that host name' do
      fresh = Fixtures.exchange('templates/crud', 'template.create', 5)
      fake = FakeClient.new([Fixtures.exchange('templates/crud', 'template.get', 12), fresh])
      name = fresh['params'].first['host']

      expect(described_class.new(fake).create_or_update(host: name, groups: [{ groupid: group }])).to eq(fresh['result']['templateids'].first.to_i)
      expect(fake.sent('template.create')).to eq([[{ 'host' => name, 'groups' => [{ 'groupid' => group }] }]])
      expect(fake.count('template.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      found = Fixtures.exchange('templates/crud', 'template.get', 13)
      fake = FakeClient.new([found])

      expect(described_class.new(fake).get_or_create(host: found['result'].first['host'])).to eq(found['result'].first['templateid'].to_i)
      expect(fake.count('template.create')).to eq(0)
    end

    it 'creates when the lookup finds nothing, filtering on the host name alone' do
      fresh = Fixtures.exchange('templates/crud', 'template.create', 6)
      fake = FakeClient.new([Fixtures.exchange('templates/crud', 'template.get', 14), fresh])
      name = fresh['params'].first['host']

      expect(described_class.new(fake).get_or_create(host: name, groups: [{ groupid: group }])).to eq(fresh['result']['templateids'].first.to_i)
      expect(fake.sent('template.get')).to eq([{ 'filter' => { 'host' => name }, 'output' => %w[templateid host] }])
      expect(fake.sent('template.create')).to eq([[{ 'host' => name, 'groups' => [{ 'groupid' => group }] }]])
    end
  end

  describe '#update' do
    it 'raises before any request when the payload names no templateid' do
      expect { templates.update(description: 'desc v1') }.to raise_error(ZabbixApi::ApiError, /templateid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end
  end

  describe '#delete' do
    it 'sends the bare id it was given and returns an Integer, template.delete answering with Strings either way' do
      by_integer = deleted['params'].first
      by_string = Fixtures.exchange('templates/crud', 'template.delete', 2)
      expect([by_integer, by_string['params'].first]).to match([an_instance_of(Integer), an_instance_of(String)])
      expect([deleted['result']['templateids'].first, by_string['result']['templateids'].first]).to all(be_an_instance_of(String))

      integer_client = FakeClient.new([deleted])
      string_client = FakeClient.new([by_string])
      expect(described_class.new(integer_client).delete(by_integer)).to eq(by_integer)
      expect(described_class.new(string_client).delete(by_string['params'].first)).to eq(by_string['params'].first.to_i)
      expect([integer_client.sent('template.delete'), string_client.sent('template.delete')]).to eq([[[by_integer]], [[by_string['params'].first]]])
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create' do
      [
        [1, /Template with host name .* already exists/],
        [2, /the parameter "groups" is missing/],
        [3, /both vendor_name and vendor_version should be either present or empty/]
      ].each do |index, reason|
        refused = described_class.new(FakeClient.new([Fixtures.exchange('templates/crud', 'template.create', index)]))
        expect { refused.create(host: host, groups: [{ groupid: group }]) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
