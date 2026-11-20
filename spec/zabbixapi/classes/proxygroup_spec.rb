# Contract: ZabbixApi::Proxygroup
#   evidence: spec/fixtures/proxygroup/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/proxygroup
#   classes:  hooks, key overridden to proxy_groupid and keys derived to proxy_groupids | create
#             wraps one object and merges no defaults | the four reads and what each sends | all
#             maps the name to an Integer id | update skips equal, issues differing, force, refuses
#             without an id | the four upsert branches and the String id create_or_update merges |
#             the three aliases | delete sends a bare id and returns an Integer whether the answer
#             holds an Integer or a String | key normalisation, four entry points and four
#             mechanisms | a server refusal reaches error_message: read-only proxy_groupid and
#             state, missing name, duplicate name, the failover_delay range, the in-use delete
#   not here: the accepted range bounds, a user macro in failover_delay and the Integer min_online -
#             server behaviour the acceptance spec asserts; bulk arrays, which Basic#create and
#             #delete handle and Basic's own spec covers; the further documented get parameters
#             (selectProxies, proxyids), one representative kept live; get_id's refusal on more than
#             one match, unreachable here because proxy group names are unique server-wide, and
#             covered by Basic's own spec
require 'spec_helper'

RSpec.describe ZabbixApi::Proxygroup do
  crud = Fixtures.exchanges('proxygroup/crud')
  row = Fixtures.exchange('proxygroup/crud', 'proxygroup.get')['result'].first
  table = Fixtures.exchange('proxygroup/crud', 'proxygroup.get', 5)['result']
  deleted = Fixtures.exchange('proxygroup/crud', 'proxygroup.delete')
  id = row['proxy_groupid'].to_i
  name = row['name']

  let(:client) { FakeClient.new(crud) }
  let(:proxygroup) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'proxygroup', identify: 'name', key: 'proxy_groupid', keys: 'proxy_groupids', default_options: {}

  it_behaves_like 'an inherited create', payload: { name: name }, defaults: {}, exchange: Fixtures.exchange('proxygroup/crud', 'proxygroup.create')
  it_behaves_like 'an inherited delete', id: deleted['result']['proxy_groupids'].first, exchange: deleted
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'proxy_groupid', value: name, rows: [row]
  it_behaves_like 'an inherited all', identify: 'name', key: 'proxy_groupid', rows: table
  it_behaves_like 'the inherited reads', identify: 'name', key: 'proxy_groupid', value: name, id: id, rows: [row]
  # No collection: proxygroup.update accepts none - a proxy joins a group through its own
  # proxy_groupid - so the output: 'extend' dump carries every property the update accepts.
  it_behaves_like 'an update that skips when unchanged', key: 'proxy_groupid', id: id, dump: [row], unchanged: { name: name }, changed: { min_online: '11' }
  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'proxy_groupid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism, not per entry point: the plain symbolize_keys of a
  # filter-building read, the conditional one in get_id, require_field! in dump_by_id, and the dump
  # comparison in update. create would be a fifth only for a class with default_options; Proxygroup
  # has none, so there it is the same mechanism as get_full_data.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { proxy_groupid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { proxy_groupid: id, name: name }, exchanges: crud

  describe '#update' do
    it 'raises before any request when the payload names no proxy_groupid' do
      expect { proxygroup.update(name: name) }.to raise_error(ZabbixApi::ApiError, /proxy_groupid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end

    it 'raises ApiError carrying the server reason in error_message, for a refused update' do
      [
        [Fixtures.exchange('proxygroup/crud', 'proxygroup.get', 8), Fixtures.exchange('proxygroup/crud', 'proxygroup.update', 1), /value must be one of 10-900/, { failover_delay: '9s' }],
        [Fixtures.exchange('proxygroup/crud', 'proxygroup.get', 9), Fixtures.exchange('proxygroup/crud', 'proxygroup.update', 2), /unexpected parameter "state"/, { state: 3 }]
      ].each do |dump, refusal, reason, payload|
        refused = described_class.new(FakeClient.new([dump, refusal]))
        expect { refused.update({ proxy_groupid: dump['result'].first['proxy_groupid'].to_i }.merge(payload)) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end

  describe '#create_or_update' do
    it 'looks the name up, dumps the object and updates it with the id merged in as a String' do
      found = Fixtures.exchange('proxygroup/crud', 'proxygroup.get', 10)['result'].first
      fake = FakeClient.new([Fixtures.exchange('proxygroup/crud', 'proxygroup.get', 10), Fixtures.exchange('proxygroup/crud', 'proxygroup.get', 11), Fixtures.exchange('proxygroup/crud', 'proxygroup.update', 3)])

      expect(described_class.new(fake).create_or_update(name: found['name'], min_online: '11')).to eq(found['proxy_groupid'].to_i)
      expect(fake.sent('proxygroup.get')).to eq([{ 'filter' => { 'name' => found['name'] }, 'output' => %w[proxy_groupid name] }, { 'filter' => { 'proxy_groupid' => found['proxy_groupid'] }, 'output' => 'extend' }])
      expect(fake.sent('proxygroup.update')).to eq([[{ 'name' => found['name'], 'min_online' => '11', 'proxy_groupid' => found['proxy_groupid'] }]])
    end

    it 'creates without any id when the name does not exist yet' do
      created = Fixtures.exchange('proxygroup/crud', 'proxygroup.create', 6)
      fake = FakeClient.new([Fixtures.exchange('proxygroup/crud', 'proxygroup.get', 12), created])
      fresh = "#{name}-new"

      expect(described_class.new(fake).create_or_update(name: fresh)).to eq(created['result']['proxy_groupids'].first.to_i)
      expect(fake.sent('proxygroup.create')).to eq([[{ 'name' => fresh }]])
      expect(fake.count('proxygroup.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      found = Fixtures.exchange('proxygroup/crud', 'proxygroup.get', 13)['result'].first
      fake = FakeClient.new([Fixtures.exchange('proxygroup/crud', 'proxygroup.get', 13)])

      expect(described_class.new(fake).get_or_create(name: found['name'])).to eq(found['proxy_groupid'].to_i)
      expect(fake.count('proxygroup.create')).to eq(0)
    end

    it 'creates when the lookup finds nothing and returns the new id' do
      created = Fixtures.exchange('proxygroup/crud', 'proxygroup.create', 7)
      fake = FakeClient.new([Fixtures.exchange('proxygroup/crud', 'proxygroup.get', 14), created])
      fresh = "#{name}-absent"

      expect(described_class.new(fake).get_or_create(name: fresh)).to eq(created['result']['proxy_groupids'].first.to_i)
      expect(fake.sent('proxygroup.get')).to eq([{ 'filter' => { 'name' => fresh }, 'output' => %w[proxy_groupid name] }])
      expect(fake.sent('proxygroup.create')).to eq([[{ 'name' => fresh }]])
    end
  end

  describe '#delete' do
    it 'sends the bare id and returns an Integer, whether the answer holds an Integer or a String' do
      echoed_integer = deleted['result']['proxy_groupids'].first
      echoed_string = Fixtures.exchange('proxygroup/crud', 'proxygroup.delete', 1)['result']['proxy_groupids'].first
      expect([echoed_integer, echoed_string]).to match([an_instance_of(Integer), an_instance_of(String)])

      by_integer = FakeClient.new([deleted])
      by_string = FakeClient.new([Fixtures.exchange('proxygroup/crud', 'proxygroup.delete', 1)])
      expect(described_class.new(by_integer).delete(echoed_integer)).to eq(echoed_integer)
      expect(described_class.new(by_string).delete(echoed_string)).to eq(echoed_string.to_i)
      expect([by_integer.sent('proxygroup.delete'), by_string.sent('proxygroup.delete')]).to eq([[[echoed_integer]], [[echoed_string]]])
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create and delete' do
      [
        [Fixtures.exchange('proxygroup/crud', 'proxygroup.create', 2), /unexpected parameter "proxy_groupid"/, ->(wrapper) { wrapper.create(name: name, proxy_groupid: 999_999) }],
        [Fixtures.exchange('proxygroup/crud', 'proxygroup.create', 3), /unexpected parameter "state"/, ->(wrapper) { wrapper.create(name: name, state: 3) }],
        [Fixtures.exchange('proxygroup/crud', 'proxygroup.create', 4), /the parameter "name" is missing/, ->(wrapper) { wrapper.create(description: 'nameless') }],
        [Fixtures.exchange('proxygroup/crud', 'proxygroup.create', 5), /already exists/, ->(wrapper) { wrapper.create(name: name) }],
        [Fixtures.exchange('proxygroup/crud', 'proxygroup.delete', 2), /is used by proxy/, ->(wrapper) { wrapper.delete(id) }]
      ].each do |exchange, reason, call|
        refused = described_class.new(FakeClient.new([exchange]))
        expect { call.call(refused) }.to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
