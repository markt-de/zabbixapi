# Contract: ZabbixApi::Usergroups
#   evidence: spec/fixtures/usergroups/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/usergroup
#   classes:  hooks, key overridden to usrgrpid | create wraps one object and merges no defaults,
#             collections included | the four reads and the request each builds | get_id filters on
#             the whole payload | all maps the name to an Integer id | the extend row carries no
#             collection, which is why a payload naming one is never skipped | update skips an equal
#             payload, issues a differing one, honours force, refuses without an id | the four
#             upsert branches, the id merged in as a String | the three aliases | delete sends a
#             bare id and returns an Integer, both recorded answers holding a String | key
#             normalisation, six entry points, six mechanisms | permissions: the hostgroup_rights it
#             builds, the default 2, an explicit 0, several ids, the two collections it drops, the
#             absent guards | update_users: one object per group, the membership as userid objects,
#             an empty list, the first id returned | a refusal reaches error_message from the first
#             request, from a later one and from an unwrapped Hash payload
#   not here: the remaining create refusals of the recording (missing name is kept as the proof that
#             no default is merged, the rest - the read-only usrgrpid, userdirectoryid outside
#             gui_access 0 and 2, gui_access 4, permission 1 - are server validation handled by the
#             one code path the kept representatives already exercise, and are asserted live);
#             update_users' missing guards, the same unguarded shape permissions stands for here;
#             logins as a group member and calls from a User-type session, which need a second
#             credential and measure the server, not the gem; the deprecated rights parameter and
#             selectRights, which the wrapper only passes through; bulk arrays, which Basic#create
#             and #delete handle and Basic's own spec covers
require 'spec_helper'

RSpec.describe ZabbixApi::Usergroups do
  crud = Fixtures.exchanges('usergroups/crud')
  row = Fixtures.exchange('usergroups/crud', 'usergroup.get')['result'].first
  table = Fixtures.exchange('usergroups/crud', 'usergroup.get', 7)['result']
  id = row['usrgrpid'].to_i
  name = row['name']
  # The ids of the recording's auxiliary objects: the payload shapes below follow the usergroup
  # reference, and only the ids come from the recording.
  collections = Fixtures.exchange('usergroups/crud', 'usergroup.create', 6)['params'].first
  hostgroupid = collections['hostgroup_rights'].first['id']
  templategroupid = collections['templategroup_rights'].first['id']
  userid = collections['users'].first['userid']

  let(:client) { FakeClient.new(crud) }
  let(:usergroups) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'usergroup', identify: 'name', key: 'usrgrpid', keys: 'usrgrpids', default_options: {}

  it_behaves_like 'an inherited create', payload: { name: name }, defaults: {}, exchange: Fixtures.exchange('usergroups/crud', 'usergroup.create')
  it_behaves_like 'an inherited delete', id: Fixtures.exchange('usergroups/crud', 'usergroup.delete')['params'].first, exchange: Fixtures.exchange('usergroups/crud', 'usergroup.delete')
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'usrgrpid', value: name, rows: [row]
  it_behaves_like 'an inherited all', identify: 'name', key: 'usrgrpid', rows: table
  it_behaves_like 'the inherited reads', identify: 'name', key: 'usrgrpid', value: name, id: id, rows: [row]
  # users, hostgroup_rights, templategroup_rights and tag_filters all replace and none of them is in
  # extend, so users stands for the four: a payload naming one is never skipped.
  it_behaves_like 'an update that skips when unchanged', key: 'usrgrpid', id: id, dump: [row], unchanged: { name: name },
                                                         changed: { name: "#{name}-renamed" }, collection: { users: [{ userid: userid }] }
  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'usrgrpid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism rather than per entry point: the plain symbolize_keys
  # of a filter-building read, the conditional one in get_id, require_field! in dump_by_id, the dump
  # comparison in update, and the class's own two methods, which symbolise their own hash before
  # reading it. create would be a seventh only for a class carrying default_options; without them
  # its mechanism is get_full_data's.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { usrgrpid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { usrgrpid: id, name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :permissions, payload: { usrgrpid: id, hostgroupids: [hostgroupid] }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update_users, payload: { usrgrpids: [id], userids: [userid] }, exchanges: crud

  describe '#create' do
    it 'sends the four collection parameters through untouched inside the one-object Array' do
      created = Fixtures.exchange('usergroups/crud', 'usergroup.create', 6)
      fake = FakeClient.new([created])
      payload = { name: collections['name'], gui_access: 3, debug_mode: 1,
                  hostgroup_rights: [{ id: hostgroupid, permission: 3 }],
                  templategroup_rights: [{ id: templategroupid, permission: 2 }],
                  tag_filters: [{ groupid: hostgroupid, tag: 'env', value: 'prod' }],
                  users: [{ userid: userid }] }

      expect(described_class.new(fake).create(payload)).to eq(created['result']['usrgrpids'].first.to_i)
      expect(fake.sent('usergroup.create')).to eq([[JSON.parse(JSON.generate(payload))]])
    end

    it 'merges no defaults, so a payload without a name reaches the server exactly as given' do
      refusal = Fixtures.exchange('usergroups/crud', 'usergroup.create', 2)
      fake = FakeClient.new([refusal])

      expect { described_class.new(fake).create(debug_mode: 0) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/the parameter "name" is missing/) }
      expect(fake.sent('usergroup.create')).to eq([[{ 'debug_mode' => 0 }]])
    end
  end

  describe '#get_raw' do
    it 'passes the four select parameters through and hands back the collections they add' do
      selected = Fixtures.exchange('usergroups/crud', 'usergroup.get', 4)
      fake = FakeClient.new([selected])
      params = { usrgrpids: [selected['result'].first['usrgrpid'].to_i], selectUsers: 'extend', selectHostGroupRights: 'extend',
                 selectTemplateGroupRights: 'extend', selectTagFilters: 'extend' }

      answered = described_class.new(fake).get_raw(params)
      expect(answered.first.keys).to include('users', 'hostgroup_rights', 'templategroup_rights', 'tag_filters')
      expect(fake.sent('usergroup.get')).to eq([JSON.parse(JSON.generate(params))])
    end

    it 'passes countOutput through and hands the String count back unconverted' do
      counted = Fixtures.exchange('usergroups/crud', 'usergroup.get', 6)
      fake = FakeClient.new([counted])

      expect(described_class.new(fake).get_raw(countOutput: true, usrgrpids: counted['params']['usrgrpids'])).to eq('2')
      expect(fake.sent('usergroup.get')).to eq([{ 'countOutput' => true, 'usrgrpids' => counted['params']['usrgrpids'] }])
    end
  end

  describe '#dump_by_id' do
    # This row is the dump the update skip compares against; that a collection payload is therefore
    # never skipped is asserted by the shared group above.
    it 'returns an extend row carrying scalar properties and none of the four collections' do
      dumped = Fixtures.exchange('usergroups/crud', 'usergroup.get', 3)
      fake = FakeClient.new([dumped])

      expect(described_class.new(fake).dump_by_id(usrgrpid: id).first.keys)
        .to include('usrgrpid', 'name', 'gui_access', 'users_status', 'debug_mode')
      expect(described_class.new(FakeClient.new([dumped])).dump_by_id(usrgrpid: id).first.keys)
        .not_to include('users', 'hostgroup_rights', 'templategroup_rights', 'tag_filters')
    end
  end

  describe '#update' do
    it 'raises before any request when the payload carries no usrgrpid, naming the guard it came from' do
      expect { usergroups.update(name: name) }.to raise_error(ZabbixApi::ApiError, /usrgrpid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end
  end

  describe '#create_or_update' do
    it 'looks the name up, dumps the object and updates it with the id merged in as a String' do
      found = Fixtures.exchange('usergroups/crud', 'usergroup.get', 14)
      target = found['result'].first
      fake = FakeClient.new([found, Fixtures.exchange('usergroups/crud', 'usergroup.get', 15), Fixtures.exchange('usergroups/crud', 'usergroup.update', 11)])

      expect(described_class.new(fake).create_or_update(name: target['name'], debug_mode: 1)).to eq(target['usrgrpid'].to_i)
      expect(fake.sent('usergroup.get')).to eq([{ 'filter' => { 'name' => target['name'] }, 'output' => %w[usrgrpid name] },
                                                { 'filter' => { 'usrgrpid' => target['usrgrpid'] }, 'output' => 'extend' }])
      expect(fake.sent('usergroup.update')).to eq([[{ 'name' => target['name'], 'debug_mode' => 1, 'usrgrpid' => target['usrgrpid'] }]])
    end

    it 'creates the payload untouched when the name exists nowhere, and issues no update' do
      created = Fixtures.exchange('usergroups/crud', 'usergroup.create', 9)
      fake = FakeClient.new([Fixtures.exchange('usergroups/crud', 'usergroup.get', 16), created])
      unseen = created['params'].first['name']

      expect(described_class.new(fake).create_or_update(name: unseen)).to eq(created['result']['usrgrpids'].first.to_i)
      expect(fake.sent('usergroup.create')).to eq([[{ 'name' => unseen }]])
      expect(fake.count('usergroup.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      found = Fixtures.exchange('usergroups/crud', 'usergroup.get', 12)
      target = found['result'].first
      fake = FakeClient.new([found])

      expect(described_class.new(fake).get_or_create(name: target['name'])).to eq(target['usrgrpid'].to_i)
      expect(fake.count('usergroup.create')).to eq(0)
    end

    it 'creates when the lookup finds nothing, filtering on the name and returning the new id' do
      created = Fixtures.exchange('usergroups/crud', 'usergroup.create', 8)
      fake = FakeClient.new([Fixtures.exchange('usergroups/crud', 'usergroup.get', 13), created])
      unseen = created['params'].first['name']

      expect(described_class.new(fake).get_or_create(name: unseen)).to eq(created['result']['usrgrpids'].first.to_i)
      expect(fake.sent('usergroup.get')).to eq([{ 'filter' => { 'name' => unseen }, 'output' => %w[usrgrpid name] }])
      expect(fake.sent('usergroup.create')).to eq([[{ 'name' => unseen }]])
    end
  end

  describe '#delete' do
    it 'sends the bare id and returns an Integer, both recorded answers holding a String' do
      numeric = Fixtures.exchange('usergroups/crud', 'usergroup.delete')
      string = Fixtures.exchange('usergroups/crud', 'usergroup.delete', 1)
      expect([numeric['result']['usrgrpids'].first, string['result']['usrgrpids'].first]).to all(be_a(String))

      by_number = FakeClient.new([numeric])
      by_string = FakeClient.new([string])
      expect(described_class.new(by_number).delete(numeric['params'].first)).to eq(numeric['params'].first)
      expect(described_class.new(by_string).delete(string['params'].first)).to eq(string['params'].first.to_i)
      expect(by_string.sent('usergroup.delete')).to eq([[string['params'].first]])
    end
  end

  describe '#permissions' do
    it 'posts one usergroup.update carrying nothing but usrgrpid and hostgroup_rights, and returns the group id' do
      granted = Fixtures.exchange('usergroups/crud', 'usergroup.update', 3)
      fake = FakeClient.new([granted])

      expect(described_class.new(fake).permissions(usrgrpid: id, hostgroupids: [hostgroupid])).to eq(id)
      expect(fake.sent('usergroup.update')).to eq([{ 'usrgrpid' => id, 'hostgroup_rights' => [{ 'permission' => 2, 'id' => hostgroupid }] }])
    end

    it 'defaults the permission to 2, read-only access, when the caller names none' do
      fake = FakeClient.new([Fixtures.exchange('usergroups/crud', 'usergroup.update', 3)])

      described_class.new(fake).permissions(usrgrpid: id, hostgroupids: [hostgroupid])
      expect(fake.sent('usergroup.update').first['hostgroup_rights'].map { |right| right['permission'] }).to eq([2])
    end

    it 'keeps an explicit permission 0, access denied' do
      denied = Fixtures.exchange('usergroups/crud', 'usergroup.update', 4)
      fake = FakeClient.new([denied])

      described_class.new(fake).permissions(usrgrpid: id, hostgroupids: [hostgroupid], permission: 0)
      expect(fake.sent('usergroup.update')).to eq([{ 'usrgrpid' => id, 'hostgroup_rights' => [{ 'permission' => 0, 'id' => hostgroupid }] }])
    end

    it 'turns every host group id into its own rights entry at the one permission given' do
      several = Fixtures.exchange('usergroups/crud', 'usergroup.update', 5)
      second = several['params']['hostgroup_rights'].last['id']
      fake = FakeClient.new([several])

      described_class.new(fake).permissions(usrgrpid: id, hostgroupids: [hostgroupid, second], permission: 3)
      expect(fake.sent('usergroup.update')).to eq([{ 'usrgrpid' => id,
                                                     'hostgroup_rights' => [{ 'permission' => 3, 'id' => hostgroupid },
                                                                            { 'permission' => 3, 'id' => second }] }])
    end

    it 'drops templategroup_rights and tag_filters instead of forwarding them' do
      dropped = Fixtures.exchange('usergroups/crud', 'usergroup.update', 6)
      fake = FakeClient.new([dropped])

      described_class.new(fake).permissions(usrgrpid: id, hostgroupids: [hostgroupid],
                                            templategroup_rights: [{ id: templategroupid, permission: 2 }],
                                            tag_filters: [{ groupid: hostgroupid, tag: 'env', value: 'prod' }])
      expect(fake.sent('usergroup.update').first.keys).to eq(%w[usrgrpid hostgroup_rights])
    end

    it 'sends a missing usrgrpid as null, and the server refuses it' do
      refusal = Fixtures.exchange('usergroups/crud', 'usergroup.update', 7)
      fake = FakeClient.new([refusal])

      expect { described_class.new(fake).permissions(hostgroupids: [hostgroupid]) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(%r{Invalid parameter "/1/usrgrpid": a number is expected}) }
      expect(fake.sent('usergroup.update')).to eq([{ 'usrgrpid' => nil, 'hostgroup_rights' => [{ 'permission' => 2, 'id' => hostgroupid }] }])
    end

    # update_users is unguarded the same way, on usrgrpids and userids.
    it 'raises NoMethodError before any request when no hostgroupids say what to grant' do
      expect { usergroups.permissions(usrgrpid: id) }.to raise_error(NoMethodError, /map/)
      expect(client.calls).to be_empty
    end
  end

  describe '#update_users' do
    it 'posts one object per user group, the membership as userid objects, and returns the first id' do
      written = Fixtures.exchange('usergroups/crud', 'usergroup.update', 8)
      group = written['params'].first['usrgrpid']
      members = written['params'].first['users'].map { |user| user['userid'] }
      fake = FakeClient.new([written])

      expect(described_class.new(fake).update_users(usrgrpids: [group], userids: members)).to eq(group)
      expect(fake.sent('usergroup.update')).to eq([[{ 'usrgrpid' => group, 'users' => members.map { |member| { 'userid' => member } } }]])
    end

    it 'writes several groups in one call, each given the same list, and returns the first of them' do
      written = Fixtures.exchange('usergroups/crud', 'usergroup.update', 9)
      groups = written['params'].map { |entry| entry['usrgrpid'] }
      fake = FakeClient.new([written])

      expect(described_class.new(fake).update_users(usrgrpids: groups, userids: [userid])).to eq(groups.first)
      expect(fake.sent('usergroup.update')).to eq([groups.map { |group| { 'usrgrpid' => group, 'users' => [{ 'userid' => userid }] } }])
    end

    it 'sends an empty users array for an empty userids list' do
      emptied = Fixtures.exchange('usergroups/crud', 'usergroup.update', 10)
      group = emptied['params'].first['usrgrpid']
      fake = FakeClient.new([emptied])

      expect(described_class.new(fake).update_users(usrgrpids: [group], userids: [])).to eq(group)
      expect(fake.sent('usergroup.update')).to eq([[{ 'usrgrpid' => group, 'users' => [] }]])
    end
  end

  describe 'a refusal the server sent back' do
    it "reaches the caller as an ApiError whose error_message joins the server's message and data" do
      fake = FakeClient.new([Fixtures.exchange('usergroups/crud', 'usergroup.create', 1)])

      expect { described_class.new(fake).create(name: name) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/\AInvalid params\.: User group .* already exists\.\z/) }
    end

    it 'reaches the caller from the second request too, the dump before it having succeeded' do
      fake = FakeClient.new([Fixtures.exchange('usergroups/crud', 'usergroup.get', 11), Fixtures.exchange('usergroups/crud', 'usergroup.update', 2)])

      expect { described_class.new(fake).update(usrgrpid: id, gui_access: 4) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/value must be one of 0, 1, 2, 3/) }
      expect(fake.count('usergroup.get')).to eq(1)
    end
  end
end
