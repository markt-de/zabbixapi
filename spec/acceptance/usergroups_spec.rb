# Contract: ZabbixApi::Usergroups live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/usergroup
#   classes:  create stores the name and the documented defaults | one enum at its top and the four
#             collections are stored and read back through their selects | a string-keyed payload
#             reaches the server | refusals: duplicate name, missing name, read-only usrgrpid,
#             userdirectoryid outside its condition, an out-of-range enum, a permission in the hole
#             of {0, 2, 3} | reads by name, by id and the whole table, the two blind-lookup guards,
#             one get_raw representative per return shape and one narrowing parameter | update
#             writes two properties at once, an unchanged update leaves the object alone, a forced
#             one returns the id and the name reads back as sent, a users payload replaces the
#             membership, an out-of-range enum is refused | permissions: the default read-only
#             level, an explicit 0, rights replace rather than merge, templategroup_rights and
#             tag_filters never arrive | update_users replaces, writes several groups at once and
#             empties on an empty list | the four upsert branches | delete removes, refuses an
#             unknown id and is permitted on a user's only group, where it should not be | the
#             credential survives every write group | aftercare, the interlock included
#   not here: hook values and wire shapes, which the unit spec asserts offline; that an unchanged
#             update sends no request, visible only in the traffic and asserted offline; logins as a
#             group member and calls from a User-type session, which need a second credential and
#             measure the server, not the gem; the deprecated rights parameter and selectRights,
#             passed through unwrapped; mfaid and userdirectoryid at their working values, which
#             need an MFA method and a user directory on the server
require 'spec_helper'

RSpec.describe 'ZabbixApi::Usergroups live', type: :acceptance do
  klass = 'usergroups'
  # A literal of the spec's own, never a real credential, and never used to log in.
  password = 'Zbxapi-Spec-Ug-7391'

  # Names a write target through the interlock, which raises for any id that predates this run.
  def safe(id)
    Live::Interlock.safe('usergroup', id)
  end

  def own_group(name, extra = {})
    Live.owns('usergroup', Live.retrying("create #{name}") { Live.session.usergroups.create({ name: name }.merge(extra)) })
  end

  def rights_of(id, select, property)
    Live.one('usergroup', usrgrpids: [id], select.to_sym => 'extend')[property].map { |right| [right['id'], right['permission']] }.sort
  end

  def members_of(id)
    Live.one('usergroup', usrgrpids: [id], selectUsers: 'extend')['users'].map { |user| user['username'] }.sort
  end

  before(:all) do
    # User groups, users and roles are not containers, so nothing is swept by name here: the
    # interlock would refuse to write to a leftover of an earlier run in any case, since it would
    # predate this run's baseline. Only the two container auxiliaries are pre-cleaned.
    Live::Interlock.establish!
    Live.preclean(klass, 'hostgroup')
    Live.preclean(klass, 'templategroup')

    @hg = Live.owns('hostgroup', Live.retrying('create hg') { Live.session.hostgroups.create(name: Live.name(klass, 'hg')) })
    @hg2 = Live.owns('hostgroup', Live.retrying('create hg2') { Live.session.hostgroups.create(name: Live.name(klass, 'hg2')) })
    @tg = Live.owns('templategroup', Live.retrying('create tg') { Live.session.templategroups.create(name: Live.name(klass, 'tg')) }) do |id|
      Live.session.templategroups.delete(id)
    end
    @role = Live.owns('role', Live.retrying('create role') { Live.session.roles.create(name: Live.name(klass, 'role'), type: 1) })
    # Groupless on purpose: usrgrps is not required, so the users outlive every group below.
    @u1 = Live.owns('user', Live.retrying('create u1') { Live.session.users.create(username: Live.name(klass, 'u1'), passwd: password, roleid: @role) })
    @u2 = Live.owns('user', Live.retrying('create u2') { Live.session.users.create(username: Live.name(klass, 'u2'), passwd: password, roleid: @role) })

    @minimal = own_group(Live.name(klass, 'minimal'))
    @full = own_group(Live.name(klass, 'full'), gui_access: 3, debug_mode: 1,
                                                hostgroup_rights: [{ id: @hg, permission: 3 }],
                                                templategroup_rights: [{ id: @tg, permission: 2 }],
                                                tag_filters: [{ groupid: @hg, tag: 'env', value: 'prod' }],
                                                users: [{ userid: @u1 }])
  end

  after(:all) do
    Live.teardown
    Live.preclean(klass, 'hostgroup')
    Live.preclean(klass, 'templategroup')
  end

  let(:usergroups) { Live.session.usergroups }

  # The credential this run uses is re-checked after every group of writes, because usergroup.update
  # can disable the group holding the token's owner.
  shared_examples 'the credential survives' do
    it 'still authenticates with the token after these writes' do
      expect(Live.retrying('alive') { Live::Interlock.alive! }).to eq(Live::Interlock.owner['username'])
    end
  end

  describe 'create' do
    it 'stores the name under the id it returned, with the three documented defaults' do
      stored = Live.one('usergroup', usrgrpids: [@minimal])
      expect(stored['name']).to eq(Live.name(klass, 'minimal'))
      expect(stored['usrgrpid'].to_i).to eq(@minimal)
      expect([stored['gui_access'], stored['users_status'], stored['debug_mode']]).to eq(%w[0 0 0])
    end

    it 'stores an enum at its documented top and every collection it was given' do
      expect(Live.one('usergroup', usrgrpids: [@full])['gui_access']).to eq('3')
      expect(rights_of(@full, 'selectHostGroupRights', 'hostgroup_rights')).to eq([[@hg.to_s, '3']])
      expect(rights_of(@full, 'selectTemplateGroupRights', 'templategroup_rights')).to eq([[@tg.to_s, '2']])
      expect(Live.one('usergroup', usrgrpids: [@full], selectTagFilters: 'extend')['tag_filters'].map { |filter| [filter['tag'], filter['value']] }).to eq([%w[env prod]])
      expect(members_of(@full)).to eq([Live.name(klass, 'u1')])
    end

    it 'accepts a string-keyed payload and the server sees the same name' do
      group = Live.owns('usergroup', Live.retrying('create strings') { usergroups.create('name' => Live.name(klass, 'strings')) })
      expect(Live.one('usergroup', usrgrpids: [group])['name']).to eq(Live.name(klass, 'strings'))
    end

    it 'refuses a name another group already carries' do
      expect { Live.retrying('create duplicate') { usergroups.create(name: Live.name(klass, 'minimal')) } }
        .to raise_error(ZabbixApi::ApiError, /User group .* already exists/)
    end

    it 'refuses a payload without a name' do
      expect { Live.retrying('create nameless') { usergroups.create(debug_mode: 0) } }
        .to raise_error(ZabbixApi::ApiError, /the parameter .*name.* is missing/)
    end

    it 'refuses the read-only usrgrpid' do
      expect { Live.retrying('create withid') { usergroups.create(name: Live.name(klass, 'withid'), usrgrpid: 99) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*usrgrpid/)
    end

    it 'refuses userdirectoryid outside the gui_access values the usergroup object reference supports it for' do
      expect { Live.retrying('create udir') { usergroups.create(name: Live.name(klass, 'udir'), gui_access: 1, userdirectoryid: 1) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*userdirectoryid/)
    end

    it 'refuses gui_access one past its top' do
      expect { Live.retrying('create guiaccess') { usergroups.create(name: Live.name(klass, 'guiaccess'), gui_access: 4) } }
        .to raise_error(ZabbixApi::ApiError, /gui_access.*value must be one of 0, 1, 2, 3/)
    end

    it 'refuses a permission of 1, which falls in the hole of the documented {0, 2, 3}' do
      expect { Live.retrying('create perm1') { usergroups.create(name: Live.name(klass, 'perm1'), hostgroup_rights: [{ id: @hg, permission: 1 }]) } }
        .to raise_error(ZabbixApi::ApiError, /permission.*value must be one of 0, 2, 3/)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'reads' do
    it 'get_id returns the id stored under that name' do
      expect(Live.retrying('get_id') { usergroups.get_id(name: Live.name(klass, 'minimal')) }).to eq(@minimal)
    end

    it 'get_id returns nil for a name no group carries' do
      expect(Live.retrying('get_id absent') { usergroups.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_id refuses to run blind' do
      expect { usergroups.get_id({}) }.to raise_error(ZabbixApi::ApiError, /name not supplied/)
    end

    it 'get_full_data returns the group under its name with gui_access, users_status, debug_mode and mfa_status' do
      found = Live.retrying('get_full_data') { usergroups.get_full_data(name: Live.name(klass, 'minimal')) }
      expect(found.map { |group| group['usrgrpid'].to_i }).to eq([@minimal])
      expect(found.first.keys).to include('gui_access', 'users_status', 'debug_mode', 'mfa_status')
    end

    it 'dump_by_id finds the group through the overridden key, carrying none of the four collections' do
      dumped = Live.retrying('dump_by_id') { usergroups.dump_by_id(usrgrpid: @full) }.first
      expect(dumped['name']).to eq(Live.name(klass, 'full'))
      expect(dumped.keys).not_to include('users', 'hostgroup_rights', 'templategroup_rights', 'tag_filters')
    end

    it 'dump_by_id refuses to run blind' do
      expect { usergroups.dump_by_id({}) }.to raise_error(ZabbixApi::ApiError, /usrgrpid not supplied/)
    end

    it 'all maps its own name to the id as an Integer and carries the stock Disabled group too' do
      table = Live.retrying('all') { usergroups.all }
      expect(table[Live.name(klass, 'minimal')]).to eq(@minimal)
      expect(table).to include('Disabled')
    end

    it 'get_raw adds the four collections when the select parameters ask for them' do
      row = Live.retrying('selects') do
        usergroups.get_raw(usrgrpids: [@full], selectUsers: 'extend', selectHostGroupRights: 'extend',
                           selectTemplateGroupRights: 'extend', selectTagFilters: 'extend')
      end.first
      expect(row.keys).to include('users', 'hostgroup_rights', 'templategroup_rights', 'tag_filters')
    end

    it 'get_raw narrows by userids to the groups that hold the user' do
      group = own_group(Live.name(klass, 'narrow'))
      Live.retrying('narrow members') { usergroups.update_users(usrgrpids: [safe(group)], userids: [@u2]) }
      names = Live.retrying('userids') { usergroups.get_raw(output: %w[name], userids: [@u2]) }.map { |found| found['name'] }
      expect(names).to include(Live.name(klass, 'narrow'))
      expect(names).not_to include(Live.name(klass, 'minimal'))
    end

    it "get_raw counts this spec's own groups as a String when countOutput is set" do
      expect(Live.retrying('countOutput') { usergroups.get_raw(countOutput: true, usrgrpids: [@minimal, @full]) }).to eq('2')
    end

    it_behaves_like 'the credential survives'
  end

  describe 'update' do
    it 'writes two properties in one call and both read back' do
      group = own_group(Live.name(klass, 'renamable'))
      expect(Live.retrying('update') { usergroups.update(usrgrpid: safe(group), name: Live.name(klass, 'renamed'), debug_mode: 1) }).to eq(group)
      stored = Live.one('usergroup', usrgrpids: [group])
      expect([stored['name'], stored['debug_mode']]).to eq([Live.name(klass, 'renamed'), '1'])
    end

    it 'returns the id and leaves the object exactly as it was when nothing differs' do
      before_state = Live.one('usergroup', usrgrpids: [@minimal])
      expect(Live.retrying('update unchanged') { usergroups.update(usrgrpid: safe(@minimal), name: Live.name(klass, 'minimal')) }).to eq(@minimal)
      expect(Live.one('usergroup', usrgrpids: [@minimal])).to eq(before_state)
    end

    it 'returns the id for a forced update, and the name reads back as sent' do
      expect(Live.retrying('update forced') { usergroups.update({ usrgrpid: safe(@minimal), name: Live.name(klass, 'minimal') }, true) }).to eq(@minimal)
      expect(Live.one('usergroup', usrgrpids: [@minimal])['name']).to eq(Live.name(klass, 'minimal'))
    end

    it 'replaces the membership through a users payload' do
      group = own_group(Live.name(klass, 'members'))
      expect(Live.retrying('members u1') { usergroups.update(usrgrpid: safe(group), users: [{ userid: @u1 }]) }).to eq(group)
      expect(members_of(group)).to eq([Live.name(klass, 'u1')])
      Live.retrying('members u2') { usergroups.update(usrgrpid: safe(group), users: [{ userid: @u2 }]) }
      expect(members_of(group)).to eq([Live.name(klass, 'u2')])
    end

    it 'refuses gui_access one past its top, and the stored value stands' do
      expect { Live.retrying('update guiaccess') { usergroups.update(usrgrpid: safe(@minimal), gui_access: 4) } }
        .to raise_error(ZabbixApi::ApiError, /gui_access.*value must be one of 0, 1, 2, 3/)
      expect(Live.one('usergroup', usrgrpids: [@minimal])['gui_access']).to eq('0')
    end

    it 'raises when no usrgrpid says which group to write' do
      expect { usergroups.update(name: Live.name(klass, 'minimal')) }.to raise_error(ZabbixApi::ApiError, /usrgrpid not supplied/)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'permissions' do
    it 'grants read-only access by default and returns the group id' do
      group = own_group(Live.name(klass, 'perm-default'))
      expect(Live.retrying('permissions default') { usergroups.permissions(usrgrpid: safe(group), hostgroupids: [@hg]) }).to eq(group)
      expect(rights_of(group, 'selectHostGroupRights', 'hostgroup_rights')).to eq([[@hg.to_s, '2']])
    end

    it 'writes an explicit permission of 0, access denied' do
      group = own_group(Live.name(klass, 'perm-deny'))
      Live.retrying('permissions deny') { usergroups.permissions(usrgrpid: safe(group), hostgroupids: [@hg], permission: 0) }
      expect(rights_of(group, 'selectHostGroupRights', 'hostgroup_rights')).to eq([[@hg.to_s, '0']])
    end

    it 'replaces the whole rights set rather than merging into it, as the usergroup.update reference states' do
      group = own_group(Live.name(klass, 'perm-replace'))
      Live.retrying('permissions both') { usergroups.permissions(usrgrpid: safe(group), hostgroupids: [@hg, @hg2], permission: 3) }
      expect(rights_of(group, 'selectHostGroupRights', 'hostgroup_rights')).to eq([[@hg.to_s, '3'], [@hg2.to_s, '3']].sort)
      Live.retrying('permissions one') { usergroups.permissions(usrgrpid: safe(group), hostgroupids: [@hg2], permission: 2) }
      expect(rights_of(group, 'selectHostGroupRights', 'hostgroup_rights')).to eq([[@hg2.to_s, '2']])
    end

    it 'cannot reach templategroup_rights or tag_filters, both reading back as they were' do
      group = own_group(Live.name(klass, 'perm-drop'), templategroup_rights: [{ id: @tg, permission: 2 }])
      Live.retrying('permissions drop') do
        usergroups.permissions(usrgrpid: safe(group), hostgroupids: [@hg],
                               templategroup_rights: [{ id: @tg, permission: 3 }],
                               tag_filters: [{ groupid: @hg, tag: 'env', value: 'prod' }])
      end
      expect(rights_of(group, 'selectHostGroupRights', 'hostgroup_rights')).to eq([[@hg.to_s, '2']])
      expect(rights_of(group, 'selectTemplateGroupRights', 'templategroup_rights')).to eq([[@tg.to_s, '2']])
      expect(Live.one('usergroup', usrgrpids: [group], selectTagFilters: 'extend')['tag_filters']).to eq([])
    end

    it 'lets a missing usrgrpid through to the server, which refuses it' do
      expect { Live.retrying('permissions blind') { usergroups.permissions(hostgroupids: [@hg]) } }
        .to raise_error(ZabbixApi::ApiError, /usrgrpid.*a number is expected/)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'update_users' do
    it 'replaces the membership with exactly the userids given and returns the first group id' do
      group = own_group(Live.name(klass, 'membership'))
      expect(Live.retrying('members both') { usergroups.update_users(usrgrpids: [safe(group)], userids: [@u1, @u2]) }).to eq(group)
      expect(members_of(group)).to eq([Live.name(klass, 'u1'), Live.name(klass, 'u2')].sort)
      Live.retrying('members one') { usergroups.update_users(usrgrpids: [safe(group)], userids: [@u1]) }
      expect(members_of(group)).to eq([Live.name(klass, 'u1')])
    end

    it 'writes several groups in one call, each given the same list' do
      first = own_group(Live.name(klass, 'multi1'))
      second = own_group(Live.name(klass, 'multi2'))
      expect(Live.retrying('members multi') { usergroups.update_users(usrgrpids: [safe(first), safe(second)], userids: [@u1, @u2]) }).to eq(first)
      expect([members_of(first), members_of(second)]).to eq([[Live.name(klass, 'u1'), Live.name(klass, 'u2')].sort] * 2)
    end

    it 'empties the group when the userids list is empty' do
      group = own_group(Live.name(klass, 'emptied'))
      Live.retrying('members before') { usergroups.update_users(usrgrpids: [safe(group)], userids: [@u1]) }
      Live.retrying('members empty') { usergroups.update_users(usrgrpids: [safe(group)], userids: []) }
      expect(members_of(group)).to eq([])
    end

    it_behaves_like 'the credential survives'
  end

  describe 'upserts' do
    it 'get_or_create returns the existing id and leaves one group of that name' do
      expect(Live.retrying('get_or_create found') { usergroups.get_or_create(name: Live.name(klass, 'minimal')) }).to eq(@minimal)
      expect(Live.count('usergroup', filter: { name: Live.name(klass, 'minimal') })).to eq(1)
    end

    it 'get_or_create creates when the name exists nowhere' do
      created = Live.owns('usergroup', Live.retrying('get_or_create create') { usergroups.get_or_create(name: Live.name(klass, 'gotten')) })
      expect(Live.one('usergroup', usrgrpids: [created])['name']).to eq(Live.name(klass, 'gotten'))
    end

    it 'create_or_update changes a property of an existing name without making a second group' do
      group = own_group(Live.name(klass, 'upserted'))
      expect(Live.retrying('upsert update') { usergroups.create_or_update(name: Live.name(klass, 'upserted'), debug_mode: 1) }).to eq(group)
      expect(Live.one('usergroup', usrgrpids: [group])['debug_mode']).to eq('1')
      expect(Live.count('usergroup', filter: { name: Live.name(klass, 'upserted') })).to eq(1)
    end

    it 'create_or_update creates when the name exists nowhere' do
      created = Live.owns('usergroup', Live.retrying('upsert create') { usergroups.create_or_update(name: Live.name(klass, 'upcreated')) })
      expect(Live.one('usergroup', usrgrpids: [created])['name']).to eq(Live.name(klass, 'upcreated'))
    end

    it_behaves_like 'the credential survives'
  end

  describe 'delete' do
    it 'removes the group and returns its id' do
      disposable = own_group(Live.name(klass, 'disposable'))
      expect(Live.retrying('delete') { usergroups.delete(safe(disposable)) }).to eq(disposable)
      Live.disown('usergroup', disposable)
      expect(Live.get('usergroup', usrgrpids: [disposable])).to eq([])
    end

    it 'refuses an id no user group carries' do
      expect { Live.retrying('delete unknown') { usergroups.delete(999999999) } }
        .to raise_error(ZabbixApi::ApiError, /No permissions to referred object or it does not exist/)
    end

    it "refuses a group that is a user's only group" do
      pending 'the server permits it, leaves the user with no group at all and thereby re-enables the account the group was disabling'
      only = Live.owns('usergroup', Live.retrying('create lastgroup') { usergroups.create(name: Live.name(klass, 'lastgroup'), users_status: 1) }) do |target|
        Live.raw('usergroup.delete', [target]) unless Live.get('usergroup', usrgrpids: [target]).empty?
      end
      member = Live.owns('user', Live.retrying('create member') do
        Live.session.users.create(username: Live.name(klass, 'member'), passwd: password, roleid: @role, usrgrps: [{ usrgrpid: only }])
      end)
      expect(Live.one('user', userids: [member], selectUsrgrps: 'extend')['usrgrps'].map { |group| group['usrgrpid'].to_i }).to eq([only])

      # As hostgroup.delete refuses a host's only group: Host "h" cannot be without host group.
      expect { Live.retrying('delete lastgroup') { usergroups.delete(safe(only)) } }
        .to raise_error(ZabbixApi::ApiError, /cannot be without/)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'aftercare' do
    it 'leaves no user group, user, role, host group or template group under its prefix once torn down, the roles, user groups and users that predate it unchanged, and the token still authenticating' do
      Live.teardown
      expect(Live.get('usergroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('user', search: { username: Live.prefix(klass) })).to eq([])
      expect(Live.get('role', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('templategroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live::Interlock.assert_unchanged!).to be(true)
      expect(Live::Interlock.alive!).to eq(Live::Interlock.owner['username'])
    end

    it 'leaves the standing hosts and proxy still present and the stock Disabled group still disabled' do
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
      expect(Live.one('usergroup', filter: { name: 'Disabled' })['users_status']).to eq('1')
    end
  end
end
