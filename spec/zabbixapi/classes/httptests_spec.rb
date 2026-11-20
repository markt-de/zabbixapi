# Contract: ZabbixApi::HttpTests
#   evidence: spec/fixtures/httptests/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/httptest
#   classes:  hooks | create wraps one object and merges the three placeholder defaults | an omitted
#             nil placeholder is dropped, an empty Array still sent | reads: by name across hosts,
#             by name and hostid, by id, raw, all | get_id refuses when nothing scopes it, a hostid
#             narrows it, and all collapses the repeated name | update skips equal, issues
#             differing, issues a collection the dump cannot show, force, refuses without an id,
#             reads the id out of the plural httptestids | both upserts scope the lookup by hostid,
#             strip it from the write, keep it on the create and merge the id as an Integer | key
#             normalisation, six entry points | aliases | delete sends a bare id and returns an
#             Integer whether the answer holds an Integer or a String | refusals: empty steps, an
#             omitted name, duplicate name, a step range, hostid on update, an unknown delete id
#   not here: the full documented parameter set and the enum and range bounds beyond the one refusal
#             representative - server validation of properties the wrapper only passes through, so
#             they belong to the acceptance spec; the web items a scenario brings with it,
#             observable only on the server; the template scenario and its inherited copy; bulk
#             arrays, which Basic#create and #delete handle and Basic's own spec covers
require 'spec_helper'

RSpec.describe ZabbixApi::HttpTests do
  crud = Fixtures.exchanges('httptests/crud')
  created = Fixtures.exchange('httptests/crud', 'httptest.create')
  deleted = Fixtures.exchange('httptests/crud', 'httptest.delete')
  row = Fixtures.exchange('httptests/crud', 'httptest.get', 5)['result'].first
  scoped = Fixtures.exchange('httptests/crud', 'httptest.get', 1)['result']
  table = Fixtures.exchange('httptests/crud', 'httptest.get', 8)['result']
  id = row['httptestid'].to_i
  name = row['name']
  hostid = row['hostid'].to_i

  # The three required properties of httptest.create, plus the two that keep a scenario inert, since
  # the server itself would poll it, plus the one step every case starts from.
  defaults = { hostid: nil, name: nil, steps: [] }
  home = { name: 'home', url: 'http://example.invalid/home', no: 1 }
  payload = { hostid: hostid, name: name, status: 1, delay: '1h', steps: [home] }
  wire_home = { 'name' => 'home', 'url' => 'http://example.invalid/home', 'no' => 1 }

  let(:client) { FakeClient.new(crud) }
  let(:httptests) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'httptest', identify: 'name', key: 'httptestid', keys: 'httptestids', default_options: { hostid: nil, name: nil, steps: [] }

  it_behaves_like 'an inherited create', payload: payload, defaults: defaults, exchange: created
  it_behaves_like 'an inherited delete', id: deleted['result']['httptestids'].first, exchange: deleted
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'httptestid', value: name, rows: scoped
  it_behaves_like 'an inherited all', identify: 'name', key: 'httptestid', rows: table
  it_behaves_like 'the inherited reads', identify: 'name', key: 'httptestid', value: name, id: id, rows: [row]
  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'httptestid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # steps and tags are never inside an extend dump, so a payload carrying one can never be proven
  # equal and the request always goes out.
  it_behaves_like 'an update that skips when unchanged', key: 'httptestid', id: id, dump: [row], unchanged: { retries: 1 }, changed: { retries: 3, agent: 'curl' }, collection: { steps: [home] }

  # One instance per distinct normalisation path: create, which merges over the symbol-keyed
  # defaults; the conditional symbolize_keys of get_id; require_field! in dump_by_id; the dump
  # comparison in update; and the two upserts, which this class overrides and which symbolize before
  # reading name and hostid out of the payload.
  it_behaves_like 'a key-normalising entry point', method: :create, payload: payload, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { httptestid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { httptestid: id, retries: 1 }, exchanges: crud
  # The three lookup-based entry points get the exchanges their call really consumes, not the whole
  # file: FakeClient replays by method name, and httptest.get[0] is the deliberately unscoped
  # two-row answer, which get_id refuses. Against a server these calls are scoped by hostid and get
  # one row, so handing them the scoped recording is the faithful replay.
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name, hostid: hostid }, exchanges: [Fixtures.exchange('httptests/crud', 'httptest.get', 1)]
  it_behaves_like 'a key-normalising entry point', method: :get_or_create, payload: payload, exchanges: [Fixtures.exchange('httptests/crud', 'httptest.get', 16)]
  it_behaves_like 'a key-normalising entry point', method: :create_or_update, payload: payload, exchanges: [Fixtures.exchange('httptests/crud', 'httptest.get', 13), Fixtures.exchange('httptests/crud', 'httptest.get', 14), Fixtures.exchange('httptests/crud', 'httptest.update', 3)]

  it_behaves_like 'a host-scoped upsert',
                  identify: 'name', key: 'httptestid', hostid: hostid, payload: payload.merge(agent: 'upserted'),
                  found: scoped, strip_on_create: false,
                  update_result: Fixtures.exchange('httptests/crud', 'httptest.update', 3)['result'],
                  create_result: Fixtures.exchange('httptests/crud', 'httptest.create', 6)['result']

  describe '#create' do
    it 'sends the forced steps placeholder as an empty Array, which the server refuses as empty rather than as missing' do
      refused = FakeClient.new([Fixtures.exchange('httptests/crud', 'httptest.create', 1)])
      expect { described_class.new(refused).create(hostid: hostid, name: name, status: 1, delay: '1h') }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/cannot be empty/) }
      expect(refused.sent('httptest.create')).to eq([[{ 'hostid' => hostid, 'name' => name, 'steps' => [], 'status' => 1, 'delay' => '1h' }]])
    end

    it 'drops the forced name placeholder instead of sending an explicit JSON null' do
      refused = FakeClient.new([Fixtures.exchange('httptests/crud', 'httptest.create', 2)])
      expect { described_class.new(refused).create(hostid: hostid, status: 1, delay: '1h', steps: [home]) }.to raise_error(ZabbixApi::ApiError)
      expect(refused.sent('httptest.create').first.first).not_to have_key('name')
    end
  end

  describe '#get_full_data' do
    it 'returns the scenarios of that name on both hosts, its filter carrying no scope' do
      found = httptests.get_full_data(name: name)
      expect(found.map { |scenario| scenario['hostid'] }.uniq.size).to eq(2)
      expect(client.sent('httptest.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => 'extend' }])
    end
  end

  describe '#get_id' do
    it 'filters on name and hostid together and returns the scenario of that one host' do
      fake = FakeClient.new([Fixtures.exchange('httptests/crud', 'httptest.get', 1)])
      expect(described_class.new(fake).get_id(name: name, hostid: hostid)).to eq(id)
      expect(fake.sent('httptest.get')).to eq([{ 'filter' => { 'name' => name, 'hostid' => hostid }, 'output' => %w[httptestid name] }])
    end

    it 'refuses two matches of one name, naming both ids, when nothing scopes the lookup' do
      unscoped = Fixtures.exchange('httptests/crud', 'httptest.get', 3)
      expect(unscoped['result'].map { |scenario| scenario['name'] }).to eq([name, name])
      ids = unscoped['result'].map { |scenario| scenario['httptestid'] }
      expect { described_class.new(FakeClient.new([unscoped])).get_id(name: name) }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 httptest objects, not one \(httptestid #{ids.join(', ')}\): narrow the lookup\z/)
    end
  end

  describe '#all' do
    it 'collapses the one name two hosts carry into a single key, the last row winning' do
      expect(table.map { |scenario| scenario['name'] }).to eq([name, name])
      expect(described_class.new(FakeClient.new([Fixtures.exchange('httptests/crud', 'httptest.get', 8)])).all).to eq(name => table.last['httptestid'].to_i)
    end
  end

  describe '#update' do
    it 'raises before any request when the payload names no httptestid' do
      expect { httptests.update(agent: 'curl') }.to raise_error(ZabbixApi::ApiError, /httptestid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end

    it 'returns the Integer id out of the httptestids the server answers with, although the httptest.update reference names the singular' do
      issued = Fixtures.exchange('httptests/crud', 'httptest.update')
      expect(issued['result'].keys).to eq(%w[httptestids])
      fake = FakeClient.new([Fixtures.exchange('httptests/crud', 'httptest.get', 10), issued])
      expect(described_class.new(fake).update(httptestid: id, retries: 3, agent: 'curl')).to eq(id)
    end

    it 'passes a hostid on to the server, which refuses it as an unexpected parameter' do
      fake = FakeClient.new([Fixtures.exchange('httptests/crud', 'httptest.get', 12), Fixtures.exchange('httptests/crud', 'httptest.update', 2)])
      expect { described_class.new(fake).update(httptestid: id, hostid: hostid, agent: 'wget') }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/unexpected parameter/) }
      expect(fake.sent('httptest.update')).to eq([[{ 'httptestid' => id, 'hostid' => hostid, 'agent' => 'wget' }]])
    end
  end

  describe '#create_or_update' do
    it 'writes every field but the hostid, with the id the lookup found merged in as an Integer' do
      fake = FakeClient.new([Fixtures.exchange('httptests/crud', 'httptest.get', 13), Fixtures.exchange('httptests/crud', 'httptest.get', 14), Fixtures.exchange('httptests/crud', 'httptest.update', 3)])
      expect(described_class.new(fake).create_or_update(payload.merge(agent: 'upserted'))).to eq(id)
      expect(fake.sent('httptest.update')).to eq([[{ 'name' => name, 'status' => 1, 'delay' => '1h', 'steps' => [wire_home], 'agent' => 'upserted', 'httptestid' => id }]])
      expect(fake.sent('httptest.update').first.first['httptestid']).to be_an(Integer)
    end
  end

  describe '#get_or_create' do
    it 'creates with the hostid httptest.create requires when the host carries no scenario of that name' do
      lookup = Fixtures.exchange('httptests/crud', 'httptest.get', 17)
      create = Fixtures.exchange('httptests/crud', 'httptest.create', 7)
      fresh = payload.merge(name: "#{name}-gotten")
      fake = FakeClient.new([lookup, create])

      expect(described_class.new(fake).get_or_create(fresh)).to eq(create['result']['httptestids'].first.to_i)
      expect(fake.sent('httptest.get')).to eq([{ 'filter' => { 'name' => fresh[:name], 'hostid' => hostid }, 'output' => %w[httptestid name] }])
      expect(fake.sent('httptest.create')).to eq([[{ 'hostid' => hostid, 'name' => fresh[:name], 'steps' => [wire_home], 'status' => 1, 'delay' => '1h' }]])
    end
  end

  describe '#delete' do
    it 'sends the bare id and returns an Integer, whether the answer holds an Integer or a String' do
      echoed_integer = deleted['result']['httptestids'].first
      echoed_string = Fixtures.exchange('httptests/crud', 'httptest.delete', 2)['result']['httptestids'].first
      expect([echoed_integer, echoed_string]).to match([an_instance_of(Integer), an_instance_of(String)])

      by_integer = FakeClient.new([deleted])
      by_string = FakeClient.new([Fixtures.exchange('httptests/crud', 'httptest.delete', 2)])
      expect(described_class.new(by_integer).delete(echoed_integer)).to eq(echoed_integer)
      expect(described_class.new(by_string).delete(echoed_string)).to eq(echoed_string.to_i)
      expect([by_integer.sent('httptest.delete'), by_string.sent('httptest.delete')]).to eq([[[echoed_integer]], [[echoed_string]]])
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create and delete' do
      [
        [Fixtures.exchange('httptests/crud', 'httptest.create', 3), /already exists/],
        [Fixtures.exchange('httptests/crud', 'httptest.create', 4), /value must be one of 1-3600/],
        [Fixtures.exchange('httptests/crud', 'httptest.delete', 3), /No permissions to referred object or it does not exist/]
      ].each do |exchange, reason|
        refused = described_class.new(FakeClient.new([exchange]))
        call = exchange['method'] == 'httptest.create' ? -> { refused.create(payload) } : -> { refused.delete(999999999) }
        expect { call.call }.to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
