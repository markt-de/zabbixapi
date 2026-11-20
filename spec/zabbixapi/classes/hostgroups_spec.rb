# Contract: ZabbixApi::HostGroups
#   evidence: spec/fixtures/hostgroups/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/hostgroup
#   classes:  hooks, key overridden to groupid | create wraps one object and merges no defaults |
#             the four reads and the request each builds | get_id filters on the whole payload and
#             refuses to run blind | all maps the name to an Integer id | update skips an equal
#             payload, issues a differing one, honours force, refuses without an id | the four
#             upsert branches, the id merged in as a String | the three aliases | delete sends a
#             bare id and returns an Integer whether the answer holds an Integer or a String | key
#             normalisation, four entry points, four mechanisms | an Array payload reaches the
#             server as one bulk request and answers an Array | a refusal reaches error_message,
#             from the first request and from a later one
#   not here: bulk delete, which Basic#delete handles and Basic's own spec covers; the mass* family
#             and propagate, which the class does not wrap; get_id's refusal on more than one match,
#             which hostgroup names being unique server-wide make unreachable here and which Basic's
#             own spec proves; the further documented get parameters of hostgroup.get, server
#             behaviour that belongs to the acceptance spec; no related collection exists on this
#             object, so the update skip has no collection case to defeat it
require 'spec_helper'

RSpec.describe ZabbixApi::HostGroups do
  crud = Fixtures.exchanges('hostgroups/crud')
  row = Fixtures.exchange('hostgroups/crud', 'hostgroup.get')['result'].first
  table = Fixtures.exchange('hostgroups/crud', 'hostgroup.get', 7)['result']
  id = row['groupid'].to_i
  name = row['name']
  # A UUIDv4 of the spec's own, not the recording's: the fake replays by method, so a payload value
  # only has to differ from the dump's for the update to be issued.
  fresh_uuid = 'c4f6a1b28d3e4f7a9b2c1d5e6f708192'

  let(:client) { FakeClient.new(crud) }
  let(:hostgroups) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'hostgroup', identify: 'name', key: 'groupid', keys: 'groupids', default_options: {}

  it_behaves_like 'an inherited create', payload: { name: name }, defaults: {}, exchange: Fixtures.exchange('hostgroups/crud', 'hostgroup.create')
  it_behaves_like 'an inherited delete', id: Fixtures.exchange('hostgroups/crud', 'hostgroup.delete')['result']['groupids'].first, exchange: Fixtures.exchange('hostgroups/crud', 'hostgroup.delete')
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'groupid', value: name, rows: [row]
  it_behaves_like 'an inherited all', identify: 'name', key: 'groupid', rows: table
  it_behaves_like 'the inherited reads', identify: 'name', key: 'groupid', value: name, id: id, rows: [row]
  # No collection: option. groupid, name, flags and uuid are the whole object and output: extend
  # returns all four, so this class has nothing the dump cannot show.
  it_behaves_like 'an update that skips when unchanged', key: 'groupid', id: id, dump: [row], unchanged: { name: name }, changed: { name: "#{name}-renamed" }
  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'groupid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism rather than per entry point: the plain symbolize_keys
  # of a filter-building read, the conditional one in get_id, require_field! in dump_by_id, and the
  # dump comparison in update. create would be a fifth only for a class carrying default_options;
  # without them its mechanism is get_full_data's.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { groupid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { groupid: id, name: name }, exchanges: crud

  describe '#create' do
    # The recording is a single-object create, so its result carries one id. That is the point: bulk
    # follows the shape of the *call*, so an Array payload answers an Array even where the server
    # made one object.
    it 'sends an Array payload as one request and answers an Array of Integers' do
      created = Fixtures.exchange('hostgroups/crud', 'hostgroup.create')
      bulk_client = FakeClient.new([created])
      bulk = [{ name: "#{name}-bulk1" }, { name: "#{name}-bulk2" }]

      expect(described_class.new(bulk_client).create(bulk)).to eq(created['result']['groupids'].map(&:to_i))
      expect(bulk_client.sent('hostgroup.create')).to eq([[{ 'name' => "#{name}-bulk1" }, { 'name' => "#{name}-bulk2" }]])
    end
  end

  describe '#get_id' do
    it 'filters on every key of the payload' do
      scoped = FakeClient.new([Fixtures.exchange('hostgroups/crud', 'hostgroup.get', 2)])

      expect(described_class.new(scoped).get_id(name: name, groupid: id)).to eq(id)
      expect(scoped.sent('hostgroup.get')).to eq([{ 'filter' => { 'name' => name, 'groupid' => id }, 'output' => %w[groupid name] }])
    end
  end

  describe '#get_raw' do
    it 'passes countOutput through and hands the String count back unconverted' do
      counted = FakeClient.new([Fixtures.exchange('hostgroups/crud', 'hostgroup.get', 6)])

      expect(described_class.new(counted).get_raw(countOutput: true, groupids: [id])).to eq('1')
      expect(counted.sent('hostgroup.get')).to eq([{ 'countOutput' => true, 'groupids' => [id] }])
    end
  end

  describe '#update' do
    it 'raises before any request when the payload carries no groupid, naming the guard it came from' do
      expect { hostgroups.update(name: name) }.to raise_error(ZabbixApi::ApiError, /groupid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end
  end

  describe '#create_or_update' do
    it 'looks the name up, dumps the object and updates it with the id merged in as a String' do
      found = Fixtures.exchange('hostgroups/crud', 'hostgroup.get', 11)
      target = found['result'].first
      fake = FakeClient.new([found, Fixtures.exchange('hostgroups/crud', 'hostgroup.get', 12), Fixtures.exchange('hostgroups/crud', 'hostgroup.update', 2)])

      expect(described_class.new(fake).create_or_update(name: target['name'], uuid: fresh_uuid)).to eq(target['groupid'].to_i)
      expect(fake.sent('hostgroup.get')).to eq([{ 'filter' => { 'name' => target['name'] }, 'output' => %w[groupid name] },
                                                { 'filter' => { 'groupid' => target['groupid'] }, 'output' => 'extend' }])
      expect(fake.sent('hostgroup.update')).to eq([[{ 'name' => target['name'], 'uuid' => fresh_uuid, 'groupid' => target['groupid'] }]])
    end

    it 'creates the payload untouched when the name exists nowhere, and issues no update' do
      created = Fixtures.exchange('hostgroups/crud', 'hostgroup.create', 7)
      fake = FakeClient.new([Fixtures.exchange('hostgroups/crud', 'hostgroup.get', 13), created])
      unseen = "#{name}-unseen"

      expect(described_class.new(fake).create_or_update(name: unseen)).to eq(created['result']['groupids'].first.to_i)
      expect(fake.sent('hostgroup.create')).to eq([[{ 'name' => unseen }]])
      expect(fake.count('hostgroup.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      found = Fixtures.exchange('hostgroups/crud', 'hostgroup.get', 14)
      target = found['result'].first
      fake = FakeClient.new([found])

      expect(described_class.new(fake).get_or_create(name: target['name'])).to eq(target['groupid'].to_i)
      expect(fake.count('hostgroup.create')).to eq(0)
    end

    it 'creates when the lookup finds nothing, filtering on the name and returning the new id' do
      created = Fixtures.exchange('hostgroups/crud', 'hostgroup.create', 8)
      fake = FakeClient.new([Fixtures.exchange('hostgroups/crud', 'hostgroup.get', 15), created])
      unseen = "#{name}-unknown"

      expect(described_class.new(fake).get_or_create(name: unseen)).to eq(created['result']['groupids'].first.to_i)
      expect(fake.sent('hostgroup.get')).to eq([{ 'filter' => { 'name' => unseen }, 'output' => %w[groupid name] }])
      expect(fake.sent('hostgroup.create')).to eq([[{ 'name' => unseen }]])
    end
  end

  describe '#delete' do
    it 'sends the bare id and returns an Integer, whether the answer holds an Integer or a String' do
      numeric = Fixtures.exchange('hostgroups/crud', 'hostgroup.delete')
      string = Fixtures.exchange('hostgroups/crud', 'hostgroup.delete', 1)
      # hostgroup.delete echoes the type it was given, which is what makes both branches of
      # parse_keys' to_i worth asserting.
      expect([numeric['result']['groupids'].first, string['result']['groupids'].first]).to match([an_instance_of(Integer), an_instance_of(String)])

      by_number = FakeClient.new([numeric])
      by_string = FakeClient.new([string])
      expect(described_class.new(by_number).delete(numeric['params'].first)).to eq(numeric['params'].first)
      expect(described_class.new(by_string).delete(string['params'].first)).to eq(string['params'].first.to_i)
      expect(by_string.sent('hostgroup.delete')).to eq([[string['params'].first]])
    end
  end

  describe 'a refusal the server sent back' do
    it "reaches the caller as an ApiError whose error_message joins the server's message and data" do
      fake = FakeClient.new([Fixtures.exchange('hostgroups/crud', 'hostgroup.create', 1)])

      expect { described_class.new(fake).create(name: name) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/\AInvalid params\.: Host group .* already exists\.\z/) }
    end

    it 'reaches the caller from the second request too, the dump before it having succeeded' do
      fake = FakeClient.new([Fixtures.exchange('hostgroups/crud', 'hostgroup.get', 10), Fixtures.exchange('hostgroups/crud', 'hostgroup.update', 1)])

      expect { described_class.new(fake).update(groupid: id, flags: 4) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/unexpected parameter .flags/) }
      expect(fake.count('hostgroup.get')).to eq(1)
    end
  end
end
