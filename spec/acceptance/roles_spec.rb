# Contract: ZabbixApi::Roles live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/role
#   classes:  create stores name and type and lets the server fill the documented rule defaults |
#             rules given on create are stored verbatim | refusals: duplicate name, type out of
#             range, readonly, a Super-admin-only UI element on a type 1 role | reads by name, by id
#             and the whole table | one get_raw representative | update writes two properties at
#             once, an unchanged and a forced one leave the role alone, readonly is refused | rules
#             merge into the stored object, and api.access 0 wipes the list | rules() merges through
#             one call and refuses at the server without a roleid | the four upsert branches |
#             delete, and the refusal while a user holds the role | the credential survives every
#             write group | aftercare
#   not here: that a readonly role refuses updates, which only a stock role can show, create and
#             update both refusing readonly, and no spec writes a stock role; the hook values and
#             every wire shape, which the unit spec asserts offline; user group membership, which
#             belongs to Usergroups; the missing-type refusal, the same validator as the type range;
#             that an unchanged update sends no request, observable only in the traffic; that an api
#             deny list really refuses a method, which needs a second session opened under that
#             role; role counts, which other clients of the same server can change at any time
require 'spec_helper'

RSpec.describe 'ZabbixApi::Roles live', type: :acceptance do
  klass = 'roles'
  # A literal of this spec's own, never a real password.
  password = 'Zbx-Spec-Roles-Quarz-93'
  full_rules = { 'ui' => [{ 'name' => 'monitoring.maps', 'status' => 0 }], 'ui.default_access' => 1,
                 'api.access' => 1, 'api.mode' => 0, 'api' => ['*.create', '*.update', '*.delete'],
                 'actions' => [{ 'name' => 'execute_scripts', 'status' => 0 }], 'actions.default_access' => 1,
                 'modules.default_access' => 0, 'services.read.mode' => 0, 'services.write.mode' => 1 }

  # Roles are not among the containers Live::CONTAINERS lists, so nothing is pre-cleaned by name: a
  # leftover would enter the interlock baseline as a role predating the spec, which the interlock
  # refuses to write. The interlock is established before the first write, and every id the examples
  # pass to update, rules, delete or destroy is named through Live::Interlock.safe; the upserts
  # resolve their own target and can only ever find a name under this prefix.
  before(:all) do
    Live::Interlock.establish!
    @one = Live.owns('role', Live.retrying('create one') { Live.session.roles.create(name: Live.name(klass, 'one'), type: 1) })
    @full = Live.owns('role', Live.retrying('create full') { Live.session.roles.create(name: Live.name(klass, 'full'), type: 1, rules: full_rules) })
    @member = Live.owns('role', Live.retrying('create member') { Live.session.roles.create(name: Live.name(klass, 'member'), type: 1) })
    @user = Live.owns('user', Live.retrying('create user') { Live.raw('user.create', username: Live.name(klass, 'u1'), passwd: password, roleid: @member)['userids'][0].to_i })
  end

  after(:all) { Live.teardown }

  let(:roles) { Live.session.roles }

  # The credential this run uses is re-checked after every group of writes, because role.update can
  # revoke the API access of the token owner's role.
  shared_examples 'the credential survives' do
    it 'still authenticates with the token after these writes' do
      expect(Live.retrying('alive') { Live::Interlock.alive! }).to eq(Live::Interlock.owner['username'])
    end
  end

  describe 'create' do
    it 'stores the name and the type, and the new role is not readonly' do
      stored = Live.one('role', roleids: [@one])
      expect(stored['name']).to eq(Live.name(klass, 'one'))
      expect([stored['roleid'].to_i, stored['type'], stored['readonly']]).to eq([@one, '1', '0'])
    end

    it 'leaves the server to fill the seven documented rule defaults and an empty api list' do
      rules = Live.one('role', roleids: [@one], selectRules: 'extend')['rules']
      expect(rules.values_at('api.access', 'api.mode', 'ui.default_access', 'modules.default_access', 'actions.default_access', 'services.read.mode', 'services.write.mode'))
        .to eq(%w[1 0 1 1 1 1 0])
      expect(rules['api']).to eq([])
    end

    it 'stores five rules a create carries: the api list, api.mode, a ui element, an action and modules.default_access' do
      rules = Live.one('role', roleids: [@full], selectRules: 'extend')['rules']
      expect(rules['api'].sort).to eq(['*.create', '*.delete', '*.update'])
      expect(rules['api.mode']).to eq('0')
      expect(rules['ui'].find { |element| element['name'] == 'monitoring.maps' }['status']).to eq('0')
      expect(rules['actions'].find { |action| action['name'] == 'execute_scripts' }['status']).to eq('0')
      expect(rules['modules.default_access']).to eq('0')
    end

    it 'refuses a name another role already carries' do
      expect { Live.retrying('create duplicate') { roles.create(name: Live.name(klass, 'one'), type: 1) } }.to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses a type outside 1, 2, 3' do
      expect { Live.retrying('create badtype') { roles.create(name: Live.name(klass, 'badtype'), type: 0) } }.to raise_error(ZabbixApi::ApiError, /value must be one of 1, 2, 3/)
    end

    it 'refuses readonly, which the role object reference marks read-only' do
      expect { Live.retrying('create readonly') { roles.create(name: Live.name(klass, 'readonly'), type: 1, readonly: 1) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter/)
    end

    it 'refuses a Super-admin-only UI element on a type 1 role' do
      expect { Live.retrying('create badui') { roles.create(name: Live.name(klass, 'badui'), type: 1, rules: { 'ui' => [{ 'name' => 'administration.general', 'status' => 1 }] }) } }
        .to raise_error(ZabbixApi::ApiError, /is not available for user role/)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'reads' do
    it 'get_id returns the id stored under that name' do
      expect(Live.retrying('get_id') { roles.get_id(name: Live.name(klass, 'one')) }).to eq(@one)
    end

    it 'get_id returns nil for a name no role carries' do
      expect(Live.retrying('get_id absent') { roles.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_full_data returns the role under its name with type and readonly, and no rules' do
      found = Live.retrying('get_full_data') { roles.get_full_data(name: Live.name(klass, 'one')) }
      expect(found.map { |role| role['roleid'].to_i }).to eq([@one])
      expect(found.first).to include('type', 'readonly')
      expect(found.first).not_to include('rules')
    end

    it 'dump_by_id returns the role with its rules' do
      dumped = Live.retrying('dump_by_id') { roles.dump_by_id(roleid: @full) }.first
      expect(dumped['roleid'].to_i).to eq(@full)
      expect(dumped['rules']['api'].sort).to eq(['*.create', '*.delete', '*.update'])
    end

    it 'get_ids_by_name returns the id as an Integer' do
      found = Live.retrying('get_ids_by_name') { roles.get_ids_by_name(name: Live.name(klass, 'one')) }
      expect(found).to eq([@one])
      expect(found.first).to be_a(Integer)
    end

    it 'get_ids_by_name returns an empty array for a name no role carries' do
      expect(Live.retrying('get_ids_by_name absent') { roles.get_ids_by_name(name: Live.name(klass, 'absent')) }).to eq([])
    end

    it 'all maps its own role name to the id as an Integer and carries the stock Super admin role too' do
      table = Live.retrying('all') { roles.all }
      expect(table[Live.name(klass, 'one')]).to eq(@one)
      expect(table).to include('Super admin role')
    end

    it 'get_raw passes the documented selectUsers through, and the role comes back with the user holding it' do
      row = Live.retrying('get_raw') { roles.get_raw(roleids: [@member], selectUsers: 'extend') }.first
      expect(row['users'].map { |user| user['username'] }).to eq([Live.name(klass, 'u1')])
    end
  end

  describe 'update' do
    it 'writes two properties in one call and both read back' do
      role = Live.owns('role', Live.retrying('create renamable') { roles.create(name: Live.name(klass, 'renamable'), type: 1) })
      expect(Live.retrying('update') { roles.update(roleid: Live::Interlock.safe('role', role), name: Live.name(klass, 'renamed'), type: 2) }).to eq(role)
      stored = Live.one('role', roleids: [role])
      expect([stored['name'], stored['type']]).to eq([Live.name(klass, 'renamed'), '2'])
    end

    it 'returns the id and leaves the role exactly as it was when nothing differs' do
      before_state = Live.one('role', roleids: [@one], selectRules: 'extend')
      expect(Live.retrying('update unchanged') { roles.update(roleid: Live::Interlock.safe('role', @one), name: Live.name(klass, 'one')) }).to eq(@one)
      expect(Live.one('role', roleids: [@one], selectRules: 'extend')).to eq(before_state)
    end

    it 'accepts a forced update that changes nothing, and the role survives it unchanged' do
      before_state = Live.one('role', roleids: [@one], selectRules: 'extend')
      expect(Live.retrying('update forced') { roles.update({ roleid: Live::Interlock.safe('role', @one), name: Live.name(klass, 'one') }, true) }).to eq(@one)
      expect(Live.one('role', roleids: [@one], selectRules: 'extend')).to eq(before_state)
    end

    it 'merges a partial rules payload into the stored rules, leaving every other sub-property intact' do
      role = Live.owns('role', Live.retrying('create merge') { roles.create(name: Live.name(klass, 'merge'), type: 1, rules: full_rules) })
      before_rules = Live.one('role', roleids: [role], selectRules: 'extend')['rules']

      Live.retrying('update rules') { roles.update(roleid: Live::Interlock.safe('role', role), rules: { 'services.read.mode' => 1 }) }

      after_rules = Live.one('role', roleids: [role], selectRules: 'extend')['rules']
      expect(after_rules['services.read.mode']).to eq('1')
      expect(after_rules.except('services.read.mode')).to eq(before_rules.except('services.read.mode'))
    end

    it 'empties the api list when api.access 0 is sent, even with a non-empty list beside it' do
      role = Live.owns('role', Live.retrying('create apilist') { roles.create(name: Live.name(klass, 'apilist'), type: 1, rules: { 'api.access' => 1, 'api.mode' => 1, 'api' => ['host.get'] }) })

      Live.retrying('update api') { roles.update(roleid: Live::Interlock.safe('role', role), rules: { 'api.access' => 0, 'api.mode' => 1, 'api' => ['host.get'] }) }

      expect(Live.one('role', roleids: [role], selectRules: 'extend')['rules']['api']).to eq([])
    end

    it 'refuses readonly on update' do
      expect { Live.retrying('update readonly') { roles.update(roleid: Live::Interlock.safe('role', @one), readonly: 1) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter/)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'rules()' do
    it 'merges the named sub-property through one call and returns the role id' do
      role = Live.owns('role', Live.retrying('create rules-method') { roles.create(name: Live.name(klass, 'rules-method'), type: 1, rules: { 'api.access' => 1, 'api.mode' => 1, 'api' => ['host.get'], 'modules.default_access' => 0 }) })

      expect(Live.retrying('rules') { roles.rules(roleid: Live::Interlock.safe('role', role), rules: { 'api.mode' => 0 }) }).to eq(role)

      stored = Live.one('role', roleids: [role], selectRules: 'extend')['rules']
      expect(stored['api.mode']).to eq('0')
      expect([stored['api'], stored['modules.default_access']]).to eq([['host.get'], '0'])
    end

    it 'is refused by the server, not by the gem, when the payload names no roleid' do
      expect { Live.retrying('rules no roleid') { roles.rules(rules: { 'api.mode' => 0 }) } }.to raise_error(ZabbixApi::ApiError, /a number is expected/)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'upserts' do
    it 'create_or_update changes a property of an existing name without duplicating the role' do
      role = Live.owns('role', Live.retrying('create upsert') { roles.create(name: Live.name(klass, 'upsert'), type: 1) })

      expect(Live.retrying('upsert update') { roles.create_or_update(name: Live.name(klass, 'upsert'), type: 2) }).to eq(role)
      expect(Live.one('role', roleids: [role])['type']).to eq('2')
      expect(Live.count('role', filter: { name: Live.name(klass, 'upsert') })).to eq(1)
    end

    it 'create_or_update creates when the name is new' do
      created = Live.owns('role', Live.retrying('upsert create') { roles.create_or_update(name: Live.name(klass, 'upserted'), type: 1) })
      expect(Live.one('role', roleids: [created])['name']).to eq(Live.name(klass, 'upserted'))
    end

    it 'get_or_create returns the existing id and leaves one role of that name' do
      expect(Live.retrying('get_or_create found') { roles.get_or_create(name: Live.name(klass, 'one'), type: 1) }).to eq(@one)
      expect(Live.count('role', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'get_or_create creates when the name is new' do
      created = Live.owns('role', Live.retrying('get_or_create create') { roles.get_or_create(name: Live.name(klass, 'gotten'), type: 1) })
      expect(Live.one('role', roleids: [created])['name']).to eq(Live.name(klass, 'gotten'))
    end

    it_behaves_like 'the credential survives'
  end

  describe 'aliases' do
    it 'add creates the role and destroy removes it' do
      added = Live.owns('role', Live.retrying('add') { roles.add(name: Live.name(klass, 'added'), type: 1) })
      expect(Live.one('role', roleids: [added])['name']).to eq(Live.name(klass, 'added'))

      expect(Live.retrying('destroy') { roles.destroy(Live::Interlock.safe('role', added)) }).to eq(added)
      Live.disown('role', added)
      expect(Live.get('role', roleids: [added])).to eq([])
    end

    it_behaves_like 'the credential survives'
  end

  describe 'delete' do
    it 'removes the role and returns its id' do
      disposable = Live.owns('role', Live.retrying('create disposable') { roles.create(name: Live.name(klass, 'disposable'), type: 1) })

      expect(Live.retrying('delete') { roles.delete(Live::Interlock.safe('role', disposable)) }).to eq(disposable)
      Live.disown('role', disposable)
      expect(Live.get('role', roleids: [disposable])).to eq([])
    end

    it 'refuses a role a user holds, which the role.delete reference does not document, and the role survives' do
      expect { Live.retrying('delete assigned') { roles.delete(Live::Interlock.safe('role', @member)) } }.to raise_error(ZabbixApi::ApiError, /Cannot delete assigned user role/)
      expect(Live.one('role', roleids: [@member])['roleid'].to_i).to eq(@member)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'aftercare' do
    it 'leaves no role or user under its prefix once torn down, the roles, user groups and users that predate it unchanged, and the standing hosts and proxy still present' do
      Live.teardown
      expect(Live.get('role', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('user', search: { username: Live.prefix(klass) })).to eq([])
      expect(Live::Interlock.assert_unchanged!).to be(true)
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
