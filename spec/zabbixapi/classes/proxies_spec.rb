# Contract: ZabbixApi::Proxies
#   evidence: spec/fixtures/proxies/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/proxy
#   classes:  hooks | create wraps one object and merges no defaults | the write-only PSK pair and
#             the documented hosts array reach the wire unchanged | the four reads and what each
#             sends | all maps the name to an Integer id | update skips equal, issues differing,
#             forces, never skips the hosts collection, refuses without an id | the four upsert
#             branches, the id merged as a String | the three aliases | delete sends a bare id and
#             returns an Integer, both recorded answers holding a String | key normalisation, four
#             entry points and four mechanisms | five server refusals reach error_message
#   not here: the ten timeout_* fields, proxy group membership and the TLS matrix beyond one case -
#             server validation of parameters the wrapper only passes through, one representative
#             each in the acceptance spec; bulk arrays, which Basic#create and #delete handle and
#             Basic's own spec covers; get_id's refusal on more than one match, unreachable here
#             because proxy names are unique server-wide, and covered by Basic's own spec
require 'spec_helper'

RSpec.describe ZabbixApi::Proxies do
  crud = Fixtures.exchanges('proxies/crud')
  # The aliases group replays each call from the first exchange of its method, and the first
  # recorded delete is the refused one, so it is given the accepted exchanges alone.
  accepted = crud.reject { |exchange| exchange.key?('error') }
  row = Fixtures.exchange('proxies/crud', 'proxy.get', 3)['result'].first
  dump_rows = Fixtures.exchange('proxies/crud', 'proxy.get', 7)['result']
  table = Fixtures.exchange('proxies/crud', 'proxy.get', 5)['result']
  deleted = Fixtures.exchange('proxies/crud', 'proxy.delete', 1)
  id = row['proxyid'].to_i
  name = row['name']

  let(:client) { FakeClient.new(crud) }
  let(:proxies) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'proxy', identify: 'name', key: 'proxyid', keys: 'proxyids', default_options: {}

  it_behaves_like 'an inherited create', payload: { name: name, operating_mode: 0 }, defaults: {}, exchange: Fixtures.exchange('proxies/crud', 'proxy.create')
  it_behaves_like 'an inherited delete', id: deleted['result']['proxyids'].first.to_i, exchange: deleted
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'proxyid', value: name, rows: [row]
  it_behaves_like 'an inherited all', identify: 'name', key: 'proxyid', rows: table
  it_behaves_like 'the inherited reads', identify: 'name', key: 'proxyid', value: name, id: id, rows: [row]
  # hosts is the proxy's related collection: output extend never returns it, so a payload naming it
  # can never be proven equal and the update is always issued.
  it_behaves_like 'an update that skips when unchanged', key: 'proxyid', id: id, dump: dump_rows, unchanged: { description: 'desc v1' }, changed: { description: 'desc v2' }, collection: { hosts: [] }
  it_behaves_like 'the aliases', exchanges: accepted, payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'proxyid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism, not per entry point: the plain symbolize_keys of a
  # filter-building read, the conditional one in get_id, require_field! in dump_by_id, and the dump
  # comparison in update. create would be a fifth only for a class with default_options; Proxies has
  # none, so its create normalises exactly as get_full_data does.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { proxyid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { proxyid: id, description: 'desc v1' }, exchanges: crud

  describe '#create' do
    it 'sends the passive address pair and the write-only PSK properties through unchanged' do
      created = Fixtures.exchange('proxies/crud', 'proxy.create', 4)
      fake = FakeClient.new([created])
      identity = 'zbxapi-spec-proxies-psk'
      psk = '0123456789abcdef0123456789abcdef'

      expect(described_class.new(fake).create(name: 'zbxapi-spec-proxies-passive', operating_mode: 1, address: '10.1.2.3', port: '10061', tls_connect: 2, tls_psk_identity: identity, tls_psk: psk)).to eq(created['result']['proxyids'].first.to_i)
      expect(fake.sent('proxy.create')).to eq([[{ 'name' => 'zbxapi-spec-proxies-passive', 'operating_mode' => 1, 'address' => '10.1.2.3', 'port' => '10061', 'tls_connect' => 2, 'tls_psk_identity' => identity, 'tls_psk' => psk }]])
    end

    it 'sends the documented hosts parameter as the array of hostid objects it was given' do
      created = Fixtures.exchange('proxies/crud', 'proxy.create', 5)
      fake = FakeClient.new([created])
      hostid = created['params'].first['hosts'].first['hostid']

      described_class.new(fake).create(name: 'zbxapi-spec-proxies-withhost', operating_mode: 0, hosts: [{ hostid: hostid }])
      expect(fake.sent('proxy.create')).to eq([[{ 'name' => 'zbxapi-spec-proxies-withhost', 'operating_mode' => 0, 'hosts' => [{ 'hostid' => hostid }] }]])
    end
  end

  describe '#update' do
    it 'raises before any request when the payload names no proxyid' do
      expect { proxies.update(name: name) }.to raise_error(ZabbixApi::ApiError, /proxyid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end

    it 'sends the hosts array beside the id, the reassignment the proxy.update reference documents' do
      fake = FakeClient.new([Fixtures.exchange('proxies/crud', 'proxy.get', 9), Fixtures.exchange('proxies/crud', 'proxy.update', 2)])
      hostid = Fixtures.exchange('proxies/crud', 'proxy.update', 2)['params'].first['hosts'].first['hostid']

      expect(described_class.new(fake).update(proxyid: id, hosts: [{ hostid: hostid }])).to eq(id)
      expect(fake.sent('proxy.update')).to eq([[{ 'proxyid' => id, 'hosts' => [{ 'hostid' => hostid }] }]])
    end
  end

  describe '#create_or_update' do
    it 'looks the name up, dumps the object by the id as a String and updates it with that id merged in' do
      found = Fixtures.exchange('proxies/crud', 'proxy.get', 11)['result'].first
      fake = FakeClient.new([Fixtures.exchange('proxies/crud', 'proxy.get', 11), Fixtures.exchange('proxies/crud', 'proxy.get', 12), Fixtures.exchange('proxies/crud', 'proxy.update', 4)])

      expect(described_class.new(fake).create_or_update(name: found['name'], description: 'via cou')).to eq(found['proxyid'].to_i)
      expect(fake.sent('proxy.get')).to eq([{ 'filter' => { 'name' => found['name'] }, 'output' => %w[proxyid name] }, { 'filter' => { 'proxyid' => found['proxyid'] }, 'output' => 'extend' }])
      expect(fake.sent('proxy.update')).to eq([[{ 'name' => found['name'], 'description' => 'via cou', 'proxyid' => found['proxyid'] }]])
    end

    it 'creates without any id when no proxy carries that name' do
      created = Fixtures.exchange('proxies/crud', 'proxy.create', 6)
      fake = FakeClient.new([Fixtures.exchange('proxies/crud', 'proxy.get', 13), created])
      fresh = 'zbxapi-spec-proxies-upserted'

      expect(described_class.new(fake).create_or_update(name: fresh, operating_mode: 0)).to eq(created['result']['proxyids'].first.to_i)
      expect(fake.sent('proxy.create')).to eq([[{ 'name' => fresh, 'operating_mode' => 0 }]])
      expect(fake.count('proxy.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      found = Fixtures.exchange('proxies/crud', 'proxy.get', 14)['result'].first
      fake = FakeClient.new([Fixtures.exchange('proxies/crud', 'proxy.get', 14)])

      expect(described_class.new(fake).get_or_create(name: found['name'])).to eq(found['proxyid'].to_i)
      expect(fake.count('proxy.create')).to eq(0)
    end

    it 'creates when the lookup finds nothing and returns the new id' do
      created = Fixtures.exchange('proxies/crud', 'proxy.create', 7)
      fake = FakeClient.new([Fixtures.exchange('proxies/crud', 'proxy.get', 15), created])
      fresh = 'zbxapi-spec-proxies-gotten'

      expect(described_class.new(fake).get_or_create(name: fresh, operating_mode: 0)).to eq(created['result']['proxyids'].first.to_i)
      expect(fake.sent('proxy.get')).to eq([{ 'filter' => { 'name' => fresh }, 'output' => %w[proxyid name] }])
      expect(fake.sent('proxy.create')).to eq([[{ 'name' => fresh, 'operating_mode' => 0 }]])
    end
  end

  describe '#delete' do
    it 'sends the bare id and returns an Integer, both recorded answers holding a String' do
      by_string = Fixtures.exchange('proxies/crud', 'proxy.delete', 2)
      integer_id = deleted['result']['proxyids'].first
      string_id = by_string['result']['proxyids'].first
      expect([integer_id, string_id]).to match([an_instance_of(String), an_instance_of(String)])

      integer_client = FakeClient.new([deleted])
      string_client = FakeClient.new([by_string])
      expect(described_class.new(integer_client).delete(integer_id.to_i)).to eq(integer_id.to_i)
      expect(described_class.new(string_client).delete(string_id)).to eq(string_id.to_i)
      expect([integer_client.sent('proxy.delete'), string_client.sent('proxy.delete')]).to eq([[[integer_id.to_i]], [[string_id]]])
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create, update and delete' do
      dump = Fixtures.exchange('proxies/crud', 'proxy.get', 8)
      [
        [[Fixtures.exchange('proxies/crud', 'proxy.create', 1)], /already exists/, ->(refused) { refused.create(name: name, operating_mode: 0) }],
        [[Fixtures.exchange('proxies/crud', 'proxy.create', 2)], /value must be 1/, ->(refused) { refused.create(name: name, operating_mode: 0, tls_connect: 2) }],
        [[Fixtures.exchange('proxies/crud', 'proxy.create', 3)], /timeout_zabbix_agent.+is missing/, ->(refused) { refused.create(name: name, operating_mode: 0, custom_timeouts: 1) }],
        [[dump, Fixtures.exchange('proxies/crud', 'proxy.update', 1)], /unexpected parameter .version./, ->(refused) { refused.update(proxyid: id, version: 987_654_321) }],
        [[Fixtures.exchange('proxies/crud', 'proxy.delete', 0)], /is monitored by proxy/, ->(refused) { refused.delete(id) }]
      ].each do |exchanges, reason, call|
        refused = described_class.new(FakeClient.new(exchanges))
        expect { call.call(refused) }.to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
