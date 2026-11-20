# Contract: ZabbixApi::Users live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/user
#   classes:  create stores the identity and leaves the documented defaults to the server | passwd
#             is never returned | every writable property but passwd and one medium round-trip | a
#             groupless user is accepted | refusals: duplicate username, missing username, read-only
#             attempt_failed, the theme enum, the password policy | reads by username, by id, the
#             dump without collections, one select* of each kind, the getAccess flag, one narrowing
#             parameter, all by membership | update writes a scalar, replaces usrgrps instead of
#             merging, leaves the object alone when nothing differs, refuses a read-only property |
#             update_medias replaces, clears, reaches two users in one call, and its two guards |
#             the four upsert branches | the writing aliases | delete removes and refuses an id no
#             user carries | the interlock: the token owner is baselined and unreachable, the
#             credential survives every write group, nothing that predates the spec changed |
#             aftercare
#   not here: the hook values and the wire shapes, which the unit spec asserts offline; that an
#             unchanged update sends no request, visible only in the traffic and asserted offline; a
#             user updating itself and the blocking of an account after failed logins, which need
#             user.login and query rather than this class, and whose unblock the gem does not wrap -
#             no account is walked towards a login lockout here; a password change, which passwd
#             being write-only makes unprovable without a login; the read-only family beyond
#             attempt_failed; the further documented get parameters mediaids, mediatypeids and
#             sortfield, one representative of each kind kept; the size of all and any other
#             server-wide count, which other clients of the same server can change at any time
require 'spec_helper'

RSpec.describe 'ZabbixApi::Users live', type: :acceptance do
  klass = 'users'
  # A literal of this spec's own, never a real credential, and long enough for the default password
  # policy.
  password = 'Kf7-Nebel-Quarz-93'

  # Users, user groups and roles are not among the containers Live::CONTAINERS lists, so nothing is
  # pre-cleaned by name: a crashed run has to be cleaned up by hand before the next one, and the
  # interlock would refuse to write whatever it left behind anyway.
  before(:all) do
    Live::Interlock.establish!
    @role = Live.owns('role', Live.retrying('create role') { Live.session.roles.create(name: Live.name(klass, 'role'), type: 1) })
    @grp = Live.owns('usergroup', Live.retrying('create grp') { Live.session.usergroups.create(name: Live.name(klass, 'grp')) })
    @grp2 = Live.owns('usergroup', Live.retrying('create grp2') { Live.session.usergroups.create(name: Live.name(klass, 'grp2')) })
    @email = Live.retrying('read the Email media type') { Live.one('mediatype', filter: { name: 'Email' }) }['mediatypeid'].to_i
    @minimal = Live.owns('user', Live.retrying('create minimal') do
      Live.session.users.create(username: Live.name(klass, 'minimal'), passwd: password, roleid: @role, usrgrps: [{ usrgrpid: @grp }])
    end)
    @full = Live.owns('user', Live.retrying('create full') do
      Live.session.users.create(username: Live.name(klass, 'full'), passwd: password, roleid: @role,
                                usrgrps: [{ usrgrpid: @grp }, { usrgrpid: @grp2 }],
                                name: 'Vor', surname: 'Nach', url: 'zabbix.php?action=dashboard.view',
                                autologin: 1, autologout: '0', lang: 'en_US', refresh: '1m',
                                rows_per_page: 100, theme: 'dark-theme', timezone: 'Europe/Berlin',
                                medias: [{ mediatypeid: @email, sendto: ['first@example.invalid'], active: 0, severity: 48, period: '1-5,09:00-18:00' }])
    end)
    @groupless = Live.owns('user', Live.retrying('create groupless') do
      Live.session.users.create(username: Live.name(klass, 'groupless'), passwd: password, roleid: @role)
    end)
  end

  after(:all) { Live.teardown }

  let(:users) { Live.session.users }

  # The credential this run uses is re-checked after every group of writes, because user.update can
  # move the token's owner out of its role or its groups.
  shared_examples 'the credential survives' do
    it 'still authenticates with the token after these writes' do
      expect(Live.retrying('alive') { Live::Interlock.alive! }).to eq(Live::Interlock.owner['username'])
    end
  end

  describe 'the interlock this class is written behind' do
    it 'baselined the token owner and refuses it as a write target' do
      expect { Live::Interlock.safe('user', Live::Interlock.owner['userid']) }.to raise_error(/INTERLOCK/)
    end

    it 'permits a user this spec created itself' do
      expect(Live::Interlock.safe('user', @minimal)).to eq(@minimal)
    end
  end

  describe 'create' do
    it 'stores the username and the role under the id it returned, and seven properties at their documented defaults' do
      stored = Live.one('user', userids: [@minimal])
      expect(stored['username']).to eq(Live.name(klass, 'minimal'))
      expect(stored['roleid'].to_i).to eq(@role)
      expect([stored['autologin'], stored['autologout'], stored['refresh'], stored['rows_per_page']]).to eq(%w[0 15m 30s 50])
      expect([stored['theme'], stored['lang'], stored['timezone']]).to eq(%w[default default default])
    end

    it 'returns no passwd in an extend read, which the user object reference marks write-only' do
      expect(Live.one('user', userids: [@minimal])).not_to have_key('passwd')
    end

    it 'stores ten properties of a full create, both its user groups, and its medium with severity and period' do
      stored = Live.one('user', userids: [@full], selectMedias: 'extend', selectUsrgrps: 'extend')
      expect([stored['name'], stored['surname'], stored['url']]).to eq(['Vor', 'Nach', 'zabbix.php?action=dashboard.view'])
      expect([stored['autologin'], stored['autologout'], stored['lang'], stored['refresh']]).to eq(%w[1 0 en_US 1m])
      expect([stored['rows_per_page'], stored['theme'], stored['timezone']]).to eq(%w[100 dark-theme Europe/Berlin])
      expect(stored['usrgrps'].map { |group| group['usrgrpid'].to_i }).to match_array([@grp, @grp2])
      medium = stored['medias'].first
      expect([medium['sendto'], medium['severity'], medium['period']]).to eq([['first@example.invalid'], '48', '1-5,09:00-18:00'])
    end

    it 'accepts a user with no user group at all, and the account really has none' do
      expect(Live.one('user', userids: [@groupless], selectUsrgrps: 'extend')['usrgrps']).to eq([])
    end

    it 'refuses a username another account already carries' do
      expect { Live.retrying('create duplicate') { users.create(username: Live.name(klass, 'minimal'), passwd: password, roleid: @role, usrgrps: [{ usrgrpid: @grp }]) } }
        .to raise_error(ZabbixApi::ApiError, /User with username .* already exists/)
    end

    it 'refuses a payload without a username' do
      expect { Live.retrying('create nameless') { users.create(passwd: password, roleid: @role, usrgrps: [{ usrgrpid: @grp }]) } }
        .to raise_error(ZabbixApi::ApiError, /the parameter .*username.* is missing/)
    end

    it 'refuses the read-only attempt_failed' do
      expect { Live.retrying('create read-only') { users.create(username: Live.name(klass, 'readonly'), passwd: password, roleid: @role, attempt_failed: 1) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*attempt_failed/)
    end

    it 'refuses a theme outside the documented enum' do
      expect { Live.retrying('create theme') { users.create(username: Live.name(klass, 'theme'), passwd: password, roleid: @role, theme: 'nope') } }
        .to raise_error(ZabbixApi::ApiError, %r{Invalid parameter .*/1/theme.*value must be one of})
    end

    it 'refuses a password the policy calls too short' do
      expect { Live.retrying('create weak') { users.create(username: Live.name(klass, 'weak'), passwd: 'short', roleid: @role, usrgrps: [{ usrgrpid: @grp }]) } }
        .to raise_error(ZabbixApi::ApiError, /must be at least 8 characters long/)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'reads' do
    it 'get_id returns the id stored under that username' do
      expect(Live.retrying('get_id') { users.get_id(username: Live.name(klass, 'minimal')) }).to eq(@minimal)
    end

    it 'get_id returns nil for a username no account carries' do
      expect(Live.retrying('get_id absent') { users.get_id(username: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_id refuses to run blind' do
      expect { users.get_id({}) }.to raise_error(ZabbixApi::ApiError, /username not supplied/)
    end

    it 'get_full_data returns the user under its username with roleid, autologout and attempt_failed' do
      found = Live.retrying('get_full_data') { users.get_full_data(username: Live.name(klass, 'minimal')) }
      expect(found.map { |user| user['userid'].to_i }).to eq([@minimal])
      expect(found.first.keys).to include('roleid', 'autologout', 'attempt_failed')
    end

    it 'dump_by_id finds the user, carrying no usrgrps, medias or role' do
      dumped = Live.retrying('dump_by_id') { users.dump_by_id(userid: @full) }.first
      expect(dumped['username']).to eq(Live.name(klass, 'full'))
      expect(dumped.keys).not_to include('usrgrps', 'medias', 'role')
    end

    it 'dump_by_id refuses to run blind' do
      expect { users.dump_by_id({}) }.to raise_error(ZabbixApi::ApiError, /userid not supplied/)
    end

    it 'get_raw passes selectUsrgrps and selectRole through and answers with usrgrps and role' do
      row = Live.retrying('selectUsrgrps') { users.get_raw(userids: [@full], selectUsrgrps: 'extend', selectRole: 'extend') }.first
      expect(row['usrgrps'].map { |group| group['usrgrpid'].to_i }).to match_array([@grp, @grp2])
      expect(row['role']['roleid'].to_i).to eq(@role)
    end

    it 'get_raw passes the getAccess flag through, which adds three properties the user object reference does not list' do
      row = Live.retrying('getAccess') { users.get_raw(userids: [@minimal], getAccess: true) }.first
      expect(row.keys).to include('gui_access', 'debug_mode', 'users_status')
    end

    it 'get_raw narrows to the members of one user group' do
      names = Live.retrying('usrgrpids') { users.get_raw(usrgrpids: [@grp2], output: ['username']) }.map { |user| user['username'] }
      expect(names).to eq([Live.name(klass, 'full')])
    end

    it 'all maps its own username to the id as an Integer and carries the stock Admin account too' do
      table = Live.retrying('all') { users.all }
      expect(table[Live.name(klass, 'minimal')]).to eq(@minimal)
      expect(table).to include('Admin')
    end
  end

  describe 'update' do
    it 'writes a scalar that reads back changed' do
      expect(Live.retrying('update name') { users.update(userid: Live::Interlock.safe('user', @minimal), name: 'Geändert') }).to eq(@minimal)
      expect(Live.one('user', userids: [@minimal])['name']).to eq('Geändert')
    end

    it 'replaces usrgrps rather than merging into them, as the user.update reference says' do
      Live.retrying('update usrgrps') { users.update(userid: Live::Interlock.safe('user', @full), usrgrps: [{ usrgrpid: @grp }]) }
      expect(Live.one('user', userids: [@full], selectUsrgrps: 'extend')['usrgrps'].map { |group| group['usrgrpid'].to_i }).to eq([@grp])
    end

    it 'returns the id and leaves the object as it was when nothing differs, the login counters and the provisioning pair aside' do
      # Read-only fields that change without an update: the login counters on a failed login as this
      # user, the provisioning pair on user.provision.
      maintained = %w[attempt_failed attempt_clock attempt_ip provisioned ts_provisioned]
      before_state = Live.one('user', userids: [@minimal]).reject { |field, _| maintained.include?(field) }
      expect(Live.retrying('update unchanged') { users.update(userid: Live::Interlock.safe('user', @minimal), name: 'Geändert') }).to eq(@minimal)
      expect(Live.one('user', userids: [@minimal]).reject { |field, _| maintained.include?(field) }).to eq(before_state)
    end

    it 'returns the id for a forced update, and the name reads back as sent' do
      expect(Live.retrying('update forced') { users.update({ userid: Live::Interlock.safe('user', @minimal), name: 'Geändert' }, true) }).to eq(@minimal)
      expect(Live.one('user', userids: [@minimal])['name']).to eq('Geändert')
    end

    it 'raises when no userid says which user to write' do
      expect { users.update(name: 'Geändert') }.to raise_error(ZabbixApi::ApiError, /userid not supplied/)
    end

    it 'refuses the read-only attempt_failed, and the stored counter stays at 0' do
      expect { Live.retrying('update read-only') { users.update(userid: Live::Interlock.safe('user', @minimal), attempt_failed: 3) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*attempt_failed/)
      expect(Live.one('user', userids: [@minimal])['attempt_failed']).to eq('0')
    end

    it_behaves_like 'the credential survives'
  end

  describe 'update_medias' do
    it 'replaces the whole media list and returns the first user id' do
      expect(Live.retrying('update_medias one') do
        users.update_medias(userids: [Live::Interlock.safe('user', @full)], medias: [{ mediatypeid: @email, sendto: ['second@example.invalid'] }])
      end).to eq(@full)
      expect(Live.one('user', userids: [@full], selectMedias: 'extend')['medias'].map { |medium| medium['sendto'] }.flatten).to eq(['second@example.invalid'])
    end

    it 'writes two media in one call' do
      Live.retrying('update_medias two') do
        users.update_medias(userids: [Live::Interlock.safe('user', @full)],
                            medias: [{ mediatypeid: @email, sendto: ['a@example.invalid'] }, { mediatypeid: @email, sendto: ['b@example.invalid'] }])
      end
      stored = Live.one('user', userids: [@full], selectMedias: 'extend')['medias'].map { |medium| medium['sendto'] }.flatten
      expect(stored).to match_array(['a@example.invalid', 'b@example.invalid'])
    end

    it 'clears the media list when it is given an empty one' do
      Live.retrying('update_medias none') { users.update_medias(userids: [Live::Interlock.safe('user', @full)], medias: []) }
      expect(Live.one('user', userids: [@full], selectMedias: 'extend')['medias']).to eq([])
    end

    it 'reaches every named user in one call, given string keys' do
      Live.retrying('update_medias two users') do
        users.update_medias('userids' => [Live::Interlock.safe('user', @full), Live::Interlock.safe('user', @groupless)],
                            'medias' => [{ mediatypeid: @email, sendto: ['both@example.invalid'] }])
      end
      [@full, @groupless].each do |user|
        expect(Live.one('user', userids: [user], selectMedias: 'extend')['medias'].map { |medium| medium['sendto'] }.flatten).to eq(['both@example.invalid'])
      end
    end

    it 'refuses a payload whose list sits under the key media, naming medias' do
      expect { users.update_medias(userids: [@full], media: [{ mediatypeid: @email, sendto: ['x@example.invalid'] }]) }
        .to raise_error(ZabbixApi::ApiError, /medias not supplied in call to update_medias/)
    end

    it 'refuses a payload without userids' do
      expect { users.update_medias(medias: []) }.to raise_error(ZabbixApi::ApiError, /userids not supplied in call to update_medias/)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'upserts' do
    it 'get_or_create returns the existing id and leaves one account of that username' do
      expect(Live.retrying('get_or_create found') { users.get_or_create(username: Live.name(klass, 'minimal')) }).to eq(@minimal)
      expect(Live.count('user', filter: { username: Live.name(klass, 'minimal') })).to eq(1)
    end

    it 'get_or_create creates when the username exists nowhere' do
      created = Live.owns('user', Live.retrying('get_or_create create') do
        users.get_or_create(username: Live.name(klass, 'goc'), passwd: password, roleid: @role, usrgrps: [{ usrgrpid: @grp }])
      end)
      expect(Live.one('user', userids: [created])['username']).to eq(Live.name(klass, 'goc'))
    end

    # The upserts resolve their own id from the username, so the interlock cannot wrap it; the
    # username is this spec's own, and Basic#create_or_update writes only where its own get_id
    # pointed, so nothing older than the run is reachable through them.
    it 'create_or_update writes a property of an existing username without making a second account' do
      expect(Live.retrying('upsert update') { users.create_or_update(username: Live.name(klass, 'goc'), surname: 'Upsert') })
        .to eq(Live.one('user', filter: { username: Live.name(klass, 'goc') })['userid'].to_i)
      expect(Live.one('user', filter: { username: Live.name(klass, 'goc') })['surname']).to eq('Upsert')
      expect(Live.count('user', filter: { username: Live.name(klass, 'goc') })).to eq(1)
    end

    it 'create_or_update creates when the username exists nowhere' do
      created = Live.owns('user', Live.retrying('upsert create') do
        users.create_or_update(username: Live.name(klass, 'cou'), passwd: password, roleid: @role, usrgrps: [{ usrgrpid: @grp }])
      end)
      expect(Live.one('user', userids: [created])['username']).to eq(Live.name(klass, 'cou'))
    end

    it_behaves_like 'the credential survives'
  end

  describe 'aliases' do
    it 'add creates the account under the username it was given' do
      added = Live.owns('user', Live.retrying('add') { users.add(username: Live.name(klass, 'added'), passwd: password, roleid: @role, usrgrps: [{ usrgrpid: @grp }]) })
      expect(Live.one('user', userids: [added])['username']).to eq(Live.name(klass, 'added'))
    end

    it 'destroy removes the account and returns its id' do
      doomed = Live.owns('user', Live.retrying('create doomed') { users.create(username: Live.name(klass, 'doomed'), passwd: password, roleid: @role, usrgrps: [{ usrgrpid: @grp }]) })
      expect(Live.retrying('destroy') { users.destroy(Live::Interlock.safe('user', doomed)) }).to eq(doomed)
      Live.disown('user', doomed)
      expect(Live.get('user', userids: [doomed])).to eq([])
    end

    it_behaves_like 'the credential survives'
  end

  describe 'delete' do
    it 'removes the account and returns its id' do
      disposable = Live.owns('user', Live.retrying('create disposable') { users.create(username: Live.name(klass, 'disposable'), passwd: password, roleid: @role, usrgrps: [{ usrgrpid: @grp }]) })
      expect(Live.retrying('delete') { users.delete(Live::Interlock.safe('user', disposable)) }).to eq(disposable)
      Live.disown('user', disposable)
      expect(Live.get('user', userids: [disposable])).to eq([])
    end

    it 'refuses an id no user carries' do
      expect { Live.retrying('delete unknown') { users.delete(999999999) } }
        .to raise_error(ZabbixApi::ApiError, /No permissions to referred object or it does not exist/)
    end

    it_behaves_like 'the credential survives'
  end

  describe 'aftercare' do
    it 'leaves no user, user group or role under its prefix once torn down, and the roles, user groups and users that predate it unchanged' do
      Live.teardown
      expect(Live.get('user', search: { username: Live.prefix(klass) })).to eq([])
      expect(Live.get('usergroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('role', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live::Interlock.assert_unchanged!).to be(true)
    end

    it 'leaves the standing hosts and proxy and the stock host group still present' do
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
      expect(Live.one('hostgroup', filter: { name: Live::GROUP_NAME })['name']).to eq(Live::GROUP_NAME)
    end
  end
end
