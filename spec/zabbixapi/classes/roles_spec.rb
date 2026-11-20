# Contract: ZabbixApi::Roles
#   evidence: spec/fixtures/roles/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/role
#   classes:  hooks | create wraps one object and merges no defaults | the reads and what each sends
#             | dump_by_id selects roleids with selectRules and takes roleid: or id: |
#             get_ids_by_name filters on name and returns Integers | all maps the name to an Integer
#             id | update skips equal, issues differing, force, and skips a rules payload too,
#             because the dump carries rules | rules() posts one role.update as an object, and a
#             missing roleid reaches the server as null | the four upsert branches | the three
#             aliases | delete sends a bare id and returns an Integer, the recorded answer holding a
#             String | key normalisation, six entry points | server refusals reach error_message
#   not here: that a readonly role refuses updates, which only a stock role can show, create and
#             update both refusing readonly; user group membership, which belongs to Usergroups;
#             role.get selectUsers, reached through the one get_raw representative; bulk arrays,
#             which Basic#create and #delete handle and Basic's own spec covers; rules()'s nil
#             branch, which role.update's Hash result never reaches; the server's own merge
#             semantics, the api list that api.access 0 empties included, which belong to the
#             acceptance spec
require 'spec_helper'

RSpec.describe ZabbixApi::Roles do
  crud = Fixtures.exchanges('roles/crud')
  row = Fixtures.exchange('roles/crud', 'role.get')['result'].first
  dumped = Fixtures.exchange('roles/crud', 'role.get', 3)
  table = Fixtures.exchange('roles/crud', 'role.get', 6)['result']
  created = Fixtures.exchange('roles/crud', 'role.create')
  deleted = Fixtures.exchange('roles/crud', 'role.delete')
  id = row['roleid'].to_i
  name = row['name']

  # The role created with rules, and the dump the update comparison of a rules payload sees.
  rules_dump = Fixtures.exchange('roles/crud', 'role.get', 13)
  full_id = rules_dump['result'].first['roleid'].to_i
  stored_rules = rules_dump['result'].first['rules']

  let(:client) { FakeClient.new(crud) }
  let(:roles) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'role', identify: 'name', key: 'roleid', keys: 'roleids', default_options: {}

  it_behaves_like 'an inherited create', payload: { name: name, type: 1 }, defaults: {}, exchange: created
  it_behaves_like 'an inherited delete', id: deleted['result']['roleids'].first.to_i, exchange: deleted
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'roleid', value: name, rows: [row]
  it_behaves_like 'an inherited all', identify: 'name', key: 'roleid', rows: table
  # dump_by_id is the class's own, so it is excluded here and asserted below.
  it_behaves_like 'the inherited reads', identify: 'name', key: 'roleid', value: name, id: id, rows: [row], except: [:dump_by_id]
  # No collection: option. The Roles dump asks for selectRules, so rules is comparable - the case
  # below proves it.
  it_behaves_like 'an update that skips when unchanged', key: 'roleid', id: id, dump: dumped['result'], unchanged: { name: name }, changed: { name: "#{name}-renamed" }
  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name, type: 1 }, id: deleted['result']['roleids'].first.to_i

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'roleid', also: [:id]
  it_behaves_like 'a lookup that refuses to run blind', method: :get_ids_by_name, field: 'name'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism: the plain symbolize_keys of a filter-building read,
  # the conditional one in get_id, the dump comparison in update, and the three the class defines
  # itself - require_id! with its extra key name, require_field!, and the explicit parameter build.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { roleid: id, name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { roleid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_ids_by_name, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :rules, payload: { roleid: id, rules: { 'api.mode' => 0 } }, exchanges: crud

  describe '#dump_by_id' do
    it 'selects by roleids and asks for the rules, which come back with the role' do
      fake = FakeClient.new([dumped])
      found = described_class.new(fake).dump_by_id(roleid: id)

      expect(fake.sent('role.get')).to eq([{ 'output' => 'extend', 'selectRules' => 'extend', 'roleids' => [id] }])
      expect(found).to eq(dumped['result'])
      expect(found.first).to include('rules')
    end

    it 'accepts the id: key and builds the same request' do
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.get', 4)])
      described_class.new(fake).dump_by_id(id: id)

      expect(fake.sent('role.get')).to eq([{ 'output' => 'extend', 'selectRules' => 'extend', 'roleids' => [id] }])
    end
  end

  describe '#get_ids_by_name' do
    it 'filters on the name, asks for extend and returns the id as an Integer' do
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.get', 7)])
      found = described_class.new(fake).get_ids_by_name(name: name)

      expect(fake.sent('role.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => 'extend' }])
      expect(found).to eq([row['roleid'].to_i])
      expect(found.first).to be_a(Integer)
    end

    it 'returns an empty array for a name no role carries' do
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.get', 8)])
      expect(described_class.new(fake).get_ids_by_name(name: "#{name}-absent")).to eq([])
    end

    it 'returns one id per row' do
      fake = FakeClient.new([{ method: 'role.get', result: [{ 'roleid' => '11', 'name' => name }, { 'roleid' => '12', 'name' => name }] }])
      expect(described_class.new(fake).get_ids_by_name(name: name)).to eq([11, 12])
    end
  end

  describe '#rules' do
    it 'posts one role.update carrying roleid and rules as an object, reads nothing first and returns the id' do
      update = Fixtures.exchange('roles/crud', 'role.update', 3)
      fake = FakeClient.new([update])
      # The id the recording used, so the call and the replayed answer describe one act; the
      # expected request is spelled out rather than taken from the recording, so a change in what
      # rules() sends fails here.
      role_id = update['params']['roleid']

      expect(described_class.new(fake).rules(roleid: role_id, rules: { 'api.mode' => 0 })).to eq(update['result']['roleids'].first.to_i)
      expect(fake.sent('role.update')).to eq([{ 'roleid' => role_id, 'rules' => { 'api.mode' => 0 } }])
      expect(fake.count('role.get')).to eq(0)
    end

    it 'sends a missing roleid as null, and the server refuses it' do
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.update', 4)])

      expect { described_class.new(fake).rules(rules: { 'api.mode' => 0 }) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(%r{"/1/roleid": a number is expected}) }
      expect(fake.sent('role.update')).to eq([{ 'roleid' => nil, 'rules' => { 'api.mode' => 0 } }])
    end
  end

  describe '#update' do
    it 'raises before any request when the payload names no roleid' do
      expect { roles.update(name: name) }.to raise_error(ZabbixApi::ApiError, /roleid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end

    it 'skips the call for a rules payload equal to the dump' do
      fake = FakeClient.new([rules_dump])

      expect(described_class.new(fake).update(roleid: full_id, rules: stored_rules)).to eq(full_id)
      expect(fake.count('role.update')).to eq(0)
    end

    it 'issues the call when one rules sub-property differs, sending the id and that payload alone' do
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.get', 14), Fixtures.exchange('roles/crud', 'role.update', 2)])

      expect(described_class.new(fake).update(roleid: full_id, rules: { 'api.mode' => 1 })).to eq(full_id)
      expect(fake.sent('role.update')).to eq([[{ 'roleid' => full_id, 'rules' => { 'api.mode' => 1 } }]])
    end

    it 'dumps first and then surfaces the refusal of a read-only property' do
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.get', 11), Fixtures.exchange('roles/crud', 'role.update', 1)])

      expect { described_class.new(fake).update(roleid: id, readonly: 1) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/unexpected parameter "readonly"/) }
      expect(fake.count('role.get')).to eq(1)
    end
  end

  describe '#create_or_update' do
    it 'looks the name up, dumps the role and updates it with the id merged in as a String' do
      found = Fixtures.exchange('roles/crud', 'role.get', 17)['result'].first
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.get', 17), Fixtures.exchange('roles/crud', 'role.get', 18), Fixtures.exchange('roles/crud', 'role.update', 5)])

      expect(described_class.new(fake).create_or_update(name: found['name'], type: 2)).to eq(found['roleid'].to_i)
      expect(fake.sent('role.get')).to eq([{ 'filter' => { 'name' => found['name'] }, 'output' => %w[roleid name] },
                                           { 'output' => 'extend', 'selectRules' => 'extend', 'roleids' => [found['roleid']] }])
      expect(fake.sent('role.update')).to eq([[{ 'name' => found['name'], 'type' => 2, 'roleid' => found['roleid'] }]])
    end

    it 'creates without any id when no role carries the name yet' do
      fresh = Fixtures.exchange('roles/crud', 'role.create', 9)
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.get', 19), fresh])

      expect(described_class.new(fake).create_or_update(name: "#{name}-cou", type: 1)).to eq(fresh['result']['roleids'].first.to_i)
      expect(fake.sent('role.create')).to eq([[{ 'name' => "#{name}-cou", 'type' => 1 }]])
      expect(fake.count('role.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      found = Fixtures.exchange('roles/crud', 'role.get', 15)['result'].first
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.get', 15)])

      expect(described_class.new(fake).get_or_create(name: found['name'], type: 2)).to eq(found['roleid'].to_i)
      expect(fake.count('role.create')).to eq(0)
    end

    it 'creates with the whole payload when the lookup finds nothing' do
      fresh = Fixtures.exchange('roles/crud', 'role.create', 8)
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.get', 16), fresh])

      expect(described_class.new(fake).get_or_create(name: "#{name}-goc", type: 1)).to eq(fresh['result']['roleids'].first.to_i)
      expect(fake.sent('role.get')).to eq([{ 'filter' => { 'name' => "#{name}-goc" }, 'output' => %w[roleid name] }])
      expect(fake.sent('role.create')).to eq([[{ 'name' => "#{name}-goc", 'type' => 1 }]])
    end
  end

  describe '#delete' do
    it 'sends the bare Integer id and returns an Integer, the recorded answer holding a String' do
      answered = deleted['result']['roleids'].first
      expect(answered).to be_a(String)

      fake = FakeClient.new([deleted])
      expect(described_class.new(fake).delete(answered.to_i)).to eq(answered.to_i)
      expect(fake.sent('role.delete')).to eq([[answered.to_i]])
    end

    it 'raises ApiError when a user holds the role' do
      fake = FakeClient.new([Fixtures.exchange('roles/crud', 'role.delete', 2)])

      expect { described_class.new(fake).delete(id) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/Cannot delete assigned user role/) }
    end
  end

  describe '#create' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create' do
      [
        [1, { name: name, type: 1 }, /already exists/],
        [2, { name: "#{name}-typeless" }, /the parameter "type" is missing/],
        [3, { name: "#{name}-badtype", type: 0 }, /value must be one of 1, 2, 3/],
        [4, { name: "#{name}-readonly", type: 1, readonly: 1 }, /unexpected parameter "readonly"/],
        [5, { name: "#{name}-badui", type: 1, rules: { 'ui' => [{ 'name' => 'administration.general', 'status' => 1 }] } }, /is not available for user role/]
      ].each do |index, payload, reason|
        refused = described_class.new(FakeClient.new([Fixtures.exchange('roles/crud', 'role.create', index)]))
        expect { refused.create(payload) }.to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
