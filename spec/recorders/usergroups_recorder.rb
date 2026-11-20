# Recorder for ZabbixApi::Usergroups: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/usergroups/crud.json.
#
# The order below is the order spec/zabbixapi/classes/usergroups_spec.rb indexes the file in: eight
# creates (two accepted, six refused), the eight reads, the four updates, the five permissions
# calls, the three update_users calls, the four upsert branches, the two writing aliases, a create
# and a delete given a String id, and a refused delete. Not recorded: a forced update, which differs
# from the skipped one only in being issued and which the shared group 'an update that skips when
# unchanged' proves offline; logins as the users created here, which need a second credential and
# show server behaviour rather than the gem's.
#
# Usergroups is an auth class, whose writes can revoke the credential the run uses, so the interlock
# is established before anything is created and every id the scenario passes to update, permissions
# or update_users is named through Live::Interlock.safe. Both the interlock and the auxiliary
# objects - two host groups, a template group, a role, two users - are built before
# Live::Recorder.start!, so the file carries usergroup traffic alone and the token-bearing
# user.checkAuthentication of the interlock never reaches it.
#
# Only the two container auxiliaries are pre-cleaned: Live::CONTAINERS covers containers, and user
# groups, users and roles are not among them - the interlock would refuse to write to a leftover of
# an earlier run in any case, since it predates this run's baseline. The ensure tears everything
# down, and the fixture is written before it, so a crashed scenario leaves no half file.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts and the
# ensure tears down.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/usergroups_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/interlock'
require_relative '../support/live/recorder'

# A refusal is one of the cases being recorded, so the exchange is what matters and the exception
# is not. Only ApiError is swallowed: a transport failure must still abort the run.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

# Names a write target through the interlock, which raises for any id that predates this run.
def safe(id)
  Live::Interlock.safe('usergroup', id)
end

klass = 'usergroups'
# A literal of the recorder's own, never a real credential; the users are created before
# Live::Recorder.start!, so it never reaches the fixture.
password = 'Zbxapi-Spec-Ug-7391'
ug = Live.session.usergroups

Live.preclean(klass, 'hostgroup')
Live.preclean(klass, 'templategroup')
Live::Interlock.establish!

hg = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'hg')))
hg2 = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'hg2')))
tg = Live.owns('templategroup', Live.retrying('create tg') { Live.session.templategroups.create(name: Live.name(klass, 'tg')) }) do |id|
  Live.session.templategroups.delete(id)
end
role = Live.owns('role', Live.session.roles.create(name: Live.name(klass, 'role'), type: 1))
# Groupless on purpose: usrgrps is not required, which keeps the users independent of the groups
# this scenario creates and deletes.
u1 = Live.owns('user', Live.session.users.create(username: Live.name(klass, 'u1'), passwd: password, roleid: role))
u2 = Live.owns('user', Live.session.users.create(username: Live.name(klass, 'u2'), passwd: password, roleid: role))

Live::Recorder.start!
begin
  # create: the accepted minimum, name alone
  minimal = Live.owns('usergroup', ug.create(name: Live.name(klass, 'minimal')))

  # create, refused: the name is taken
  refused { ug.create(name: Live.name(klass, 'minimal')) }

  # create, refused: debug_mode without the required name
  refused { ug.create(debug_mode: 0) }

  # create, refused: the read-only usrgrpid
  refused { ug.create(name: Live.name(klass, 'withid'), usrgrpid: 99) }

  # create, refused: userdirectoryid with gui_access 1, where the usergroup object reference
  # supports it with gui_access 0 or 2 only
  refused { ug.create(name: Live.name(klass, 'udir'), gui_access: 1, userdirectoryid: 1) }

  # create, refused: gui_access 4, one past the top
  refused { ug.create(name: Live.name(klass, 'guiaccess'), gui_access: 4) }

  # create: the four collections in one call, with one enum at its documented top
  full = Live.owns('usergroup', ug.create(name: Live.name(klass, 'full'), gui_access: 3, debug_mode: 1,
                                          hostgroup_rights: [{ id: hg, permission: 3 }],
                                          templategroup_rights: [{ id: tg, permission: 2 }],
                                          tag_filters: [{ groupid: hg, tag: 'env', value: 'prod' }],
                                          users: [{ userid: u1 }]))

  # create, refused: permission 1 falls in the hole of the documented {0, 2, 3}
  refused { ug.create(name: Live.name(klass, 'perm1'), hostgroup_rights: [{ id: hg, permission: 1 }]) }

  # the reads
  ug.get_full_data(name: Live.name(klass, 'minimal'))
  ug.get_id(name: Live.name(klass, 'minimal'))
  ug.get_id(name: Live.name(klass, 'absent'))
  ug.dump_by_id(usrgrpid: minimal)
  ug.get_raw(usrgrpids: [full], selectUsers: 'extend', selectHostGroupRights: 'extend',
             selectTemplateGroupRights: 'extend', selectTagFilters: 'extend')
  ug.get_raw(output: %w[name], userids: [u1])
  ug.get_raw(countOutput: true, usrgrpids: [minimal, full])
  ug.all

  # update, skipped: the payload already matches the dump, so only the dump goes out
  ug.update(usrgrpid: safe(minimal), name: Live.name(klass, 'minimal'))

  # update, issued: two properties at once
  ug.update(usrgrpid: safe(minimal), name: Live.name(klass, 'renamed'), debug_mode: 1)

  # update, issued although the value is unchanged: users is never in extend, so the dump cannot
  # prove it equal and skip_update? refuses to skip
  ug.update(usrgrpid: safe(full), users: [{ userid: u1 }])

  # update, refused: gui_access 4, one past the top
  refused { ug.update(usrgrpid: safe(minimal), gui_access: 4) }

  # permissions: no permission given, so the default 2, read-only access
  ug.permissions(usrgrpid: safe(minimal), hostgroupids: [hg])

  # permissions: an explicit 0, access denied
  ug.permissions(usrgrpid: safe(minimal), hostgroupids: [hg], permission: 0)

  # permissions: one rights entry per host group id, all at the same level
  ug.permissions(usrgrpid: safe(minimal), hostgroupids: [hg, hg2], permission: 3)

  # permissions: templategroup_rights and tag_filters are dropped rather than forwarded
  ug.permissions(usrgrpid: safe(minimal), hostgroupids: [hg],
                 templategroup_rights: [{ id: tg, permission: 2 }],
                 tag_filters: [{ groupid: hg, tag: 'env', value: 'prod' }])

  # permissions, refused: there is no id guard, so a missing usrgrpid reaches the server as null
  refused { ug.permissions(hostgroupids: [hg]) }

  # update_users: one group given two users
  ug.update_users(usrgrpids: [safe(full)], userids: [u1, u2])

  # update_users: several groups in one call, each given the same list
  ug.update_users(usrgrpids: [safe(full), safe(minimal)], userids: [u1])

  # update_users: an empty userids list
  ug.update_users(usrgrpids: [safe(full)], userids: [])

  # get_or_create, found branch: minimal carries the renamed name since the update above
  ug.get_or_create(name: Live.name(klass, 'renamed'))

  # get_or_create, create branch
  Live.owns('usergroup', ug.get_or_create(name: Live.name(klass, 'goc')))

  # create_or_update, update branch: the name exists, debug_mode differs
  ug.create_or_update(name: Live.name(klass, 'goc'), debug_mode: 1)

  # create_or_update, create branch
  Live.owns('usergroup', ug.create_or_update(name: Live.name(klass, 'cou')))

  # the two writing aliases; destroy is given an Integer id
  added = Live.owns('usergroup', ug.add(name: Live.name(klass, 'added')))
  ug.destroy(added)
  Live.disown('usergroup', added)

  # delete given a String id, where destroy above was given an Integer
  disposable = Live.owns('usergroup', ug.create(name: Live.name(klass, 'disposable')))
  ug.delete(disposable.to_s)
  Live.disown('usergroup', disposable)

  # delete, refused: an id no user group carries
  refused { ug.delete(999999999) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
  Live.preclean(klass, 'hostgroup')
  Live.preclean(klass, 'templategroup')
end
