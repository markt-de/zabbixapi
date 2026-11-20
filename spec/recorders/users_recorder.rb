# Recorder for ZabbixApi::Users: runs the cases below against the server ZABBIX_URL names, through
# the gem itself, and writes spec/fixtures/users/crud.json.
#
# Users is an auth class, whose writes can revoke the credential the run uses, so the interlock is
# established before the first write and every user the scenario writes to by id is named through
# Live::Interlock.safe: the token's owner cannot be reached from here. The interlock, the role, the
# two user groups and the lookup of the stock Email media type all come before
# Live::Recorder.start!, so the fixture carries user.* exchanges only and the token, which travels
# as a parameter of user.checkAuthentication, never enters the file.
#
# The order below is the order spec/zabbixapi/classes/users_spec.rb indexes the file in: eight
# creates (two accepted, five refused, one groupless), the eight reads, five updates (issued,
# skipped, forced, a collection the dump cannot show, refused), the five update_medias calls, the
# four upsert branches, the two writing aliases, two creates and their deletes given an Integer and
# a String id, and a refused delete. Not recorded: the local guards of update_medias, which raise
# before any request and so produce no exchange; a user updating itself and the blocking of an
# account after failed logins with its user.unblock, which go through user.login and query rather
# than this class; a password change, which no read can confirm because passwd is write-only.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so a
# gem call that sends two requests and meets a transient on the second records the first twice. A
# transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts and the
# ensure tears down. Users, user groups and roles are not among the containers Live::CONTAINERS
# lists, so nothing is pre-cleaned; a crashed run is cleaned up by hand before a re-run.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/users_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/interlock'
require_relative '../support/live/recorder'

# A literal of the recorder's own, never a real credential, and long enough for the default password
# policy; the recorder scrubs every passwd value on the way into the file anyway.
PASSWORD = 'Kf7-Nebel-Quarz-93'.freeze

# A refusal is one of the cases being recorded, so the exchange is what matters and the exception is
# not. Only ApiError is swallowed: a transport failure must still abort the run.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

klass = 'users'
users = Live.session.users

Live::Interlock.establish!
role = Live.owns('role', Live.session.roles.create(name: Live.name(klass, 'role'), type: 1))
grp = Live.owns('usergroup', Live.session.usergroups.create(name: Live.name(klass, 'grp')))
grp2 = Live.owns('usergroup', Live.session.usergroups.create(name: Live.name(klass, 'grp2')))
email = Live.one('mediatype', filter: { name: 'Email' })['mediatypeid'].to_i

Live::Recorder.start!
begin
  # create: username, passwd, roleid and one user group
  minimal = Live.owns('user', users.create(username: Live.name(klass, 'minimal'), passwd: PASSWORD, roleid: role, usrgrps: [{ usrgrpid: grp }]))

  # create, refused: the username is taken
  refused { users.create(username: Live.name(klass, 'minimal'), passwd: PASSWORD, roleid: role, usrgrps: [{ usrgrpid: grp }]) }

  # create, refused: passwd, roleid and a user group without the required username
  refused { users.create(passwd: PASSWORD, roleid: role, usrgrps: [{ usrgrpid: grp }]) }

  # create, refused: the read-only attempt_failed
  refused { users.create(username: Live.name(klass, 'readonly'), passwd: PASSWORD, roleid: role, attempt_failed: 1) }

  # create, refused: a theme outside its enum
  refused { users.create(username: Live.name(klass, 'theme'), passwd: PASSWORD, roleid: role, theme: 'nope') }

  # create, refused: the password policy rejects a short password
  refused { users.create(username: Live.name(klass, 'weak'), passwd: 'short', roleid: role, usrgrps: [{ usrgrpid: grp }]) }

  # create: every writable property in one call, two user groups and one medium
  full = Live.owns('user', users.create(username: Live.name(klass, 'full'), passwd: PASSWORD, roleid: role,
                                        usrgrps: [{ usrgrpid: grp }, { usrgrpid: grp2 }],
                                        name: 'Vor', surname: 'Nach', url: 'zabbix.php?action=dashboard.view',
                                        autologin: 1, autologout: '0', lang: 'en_US', refresh: '1m',
                                        rows_per_page: 100, theme: 'dark-theme', timezone: 'Europe/Berlin',
                                        medias: [{ mediatypeid: email, sendto: ['first@example.invalid'], active: 0, severity: 48, period: '1-5,09:00-18:00' }]))

  # create: no usrgrps at all, which the user.create reference does not mark as required and the
  # server accepts
  groupless = Live.owns('user', users.create(username: Live.name(klass, 'groupless'), passwd: PASSWORD, roleid: role))

  # the reads
  users.get_id(username: Live.name(klass, 'minimal'))
  users.get_id(username: Live.name(klass, 'absent'))
  users.get_full_data(username: Live.name(klass, 'minimal'))
  users.dump_by_id(userid: minimal)
  users.get_raw(userids: [full], selectMedias: 'extend')
  users.get_raw(userids: [full], getAccess: true)
  users.get_raw(usrgrpids: [grp2], output: ['username'])
  users.all

  # update, issued: one scalar the extend dump carries
  users.update(userid: Live::Interlock.safe('user', minimal), name: 'Geändert')

  # update, skipped: the payload now matches the dump, so only the dump goes out
  users.update(userid: Live::Interlock.safe('user', minimal), name: 'Geändert')

  # update, forced: the same payload, issued regardless
  users.update({ userid: Live::Interlock.safe('user', minimal), name: 'Geändert' }, true)

  # update, issued: usrgrps, a collection the extend dump does not return
  users.update(userid: Live::Interlock.safe('user', full), usrgrps: [{ usrgrpid: grp }])

  # update, refused: the read-only attempt_failed
  refused { users.update(userid: Live::Interlock.safe('user', minimal), attempt_failed: 3) }

  # update_medias: one user, one medium
  users.update_medias(userids: [Live::Interlock.safe('user', full)], medias: [{ mediatypeid: email, sendto: ['second@example.invalid'] }])

  # update_medias: two media in one call
  users.update_medias(userids: [Live::Interlock.safe('user', full)],
                      medias: [{ mediatypeid: email, sendto: ['a@example.invalid'] }, { mediatypeid: email, sendto: ['b@example.invalid'] }])

  # update_medias: an empty list, which passes the require_field! guard
  users.update_medias(userids: [Live::Interlock.safe('user', full)], medias: [])

  # update_medias: the same call with string keys, reaching the same wire shape
  users.update_medias('userids' => [Live::Interlock.safe('user', full)], 'medias' => [])

  # update_medias: two users in one request, one object per user id
  users.update_medias(userids: [Live::Interlock.safe('user', full), Live::Interlock.safe('user', groupless)],
                      medias: [{ mediatypeid: email, sendto: ['both@example.invalid'] }])

  # get_or_create, found branch: the lookup alone, no create
  users.get_or_create(username: Live.name(klass, 'minimal'))

  # get_or_create, create branch
  Live.owns('user', users.get_or_create(username: Live.name(klass, 'goc'), passwd: PASSWORD, roleid: role, usrgrps: [{ usrgrpid: grp }]))

  # create_or_update, update branch: the username exists, so the surname is written under the id the
  # lookup resolves; the interlock cannot wrap an id the method resolves for itself, and the
  # username is the one the get_or_create case above created, so nothing older than the run can be
  # reached
  users.create_or_update(username: Live.name(klass, 'goc'), surname: 'Upsert')

  # create_or_update, create branch
  Live.owns('user', users.create_or_update(username: Live.name(klass, 'cou'), passwd: PASSWORD, roleid: role, usrgrps: [{ usrgrpid: grp }]))

  # the two writing aliases; destroy is given an Integer id
  added = Live.owns('user', users.add(username: Live.name(klass, 'added'), passwd: PASSWORD, roleid: role, usrgrps: [{ usrgrpid: grp }]))
  users.destroy(Live::Interlock.safe('user', added))
  Live.disown('user', added)

  # delete given an Integer id, and delete given a String id; the server answers a String for both
  doomed = Live.owns('user', users.create(username: Live.name(klass, 'doomed'), passwd: PASSWORD, roleid: role, usrgrps: [{ usrgrpid: grp }]))
  disposable = Live.owns('user', users.create(username: Live.name(klass, 'disposable'), passwd: PASSWORD, roleid: role, usrgrps: [{ usrgrpid: grp }]))
  users.delete(Live::Interlock.safe('user', doomed))
  Live.disown('user', doomed)
  users.delete(Live::Interlock.safe('user', disposable).to_s)
  Live.disown('user', disposable)

  # delete, refused: an id no user carries, which the user.delete reference documents no answer for
  refused { users.delete(999999999) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
