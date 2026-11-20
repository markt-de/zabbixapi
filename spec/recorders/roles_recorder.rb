# Recorder for ZabbixApi::Roles: runs the cases below against the server ZABBIX_URL names, through
# the gem itself, and writes spec/fixtures/roles/crud.json.
#
# The order below is the order the unit spec indexes the file in: seven creates (two accepted, five
# refused), the nine reads, five updates (skipped, issued, refused, and, after a read of the stored
# rules, a rules payload skipped and issued), a create and the two rules() calls, the four upsert
# branches, the two writing aliases, a create and its delete, and a refused delete. Not recorded: a
# forced update, which differs from the skipped one only in being issued and which the shared
# example group proves offline; the bulk array forms, which Basic#create and #delete handle and
# Basic's own spec covers; `api.access: 0` wiping its own list, a server behaviour the acceptance
# spec asserts.
#
# Roles is an auth class, whose writes can revoke the credential the run uses, so the interlock is
# established before the first write and every id the scenario passes to update, rules, delete or
# destroy is named through Live::Interlock.safe. Nothing is pre-cleaned by name, since roles are not
# among the containers Live::CONTAINERS lists: the run refuses to start on a leftover role instead,
# because the interlock would count it as predating the run and refuse to write it.
#
# The user that makes the delete refusal possible is built before the recording starts, so the
# fixture carries role.* exchanges only.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts and the
# ensure tears down.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/roles_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/interlock'
require_relative '../support/live/recorder'

# Swallows the refusal a case is recorded for, and registers what an unexpectedly accepted create
# would otherwise leave behind.
def refused(own: false)
  id = yield
  Live.owns('role', id) if own && id.is_a?(Integer)
  nil
rescue ZabbixApi::ApiError
  nil
end

klass = 'roles'
password = 'Zbx-Spec-Roles-Quarz-93'
roles = Live.session.roles

leftovers = Live.get('role', search: { name: Live.prefix(klass) }).map { |role| role['name'] }
raise "roles left over from an earlier run: #{leftovers.join(', ')}" unless leftovers.empty?

Live::Interlock.establish!

# The fixture the delete refusal needs: a role and a user holding it.
member = Live.owns('role', roles.create(name: Live.name(klass, 'member'), type: 1))
Live.owns('user', Live.raw('user.create', username: Live.name(klass, 'u1'), passwd: password, roleid: member)['userids'][0].to_i)

Live::Recorder.start!
begin
  # create: the accepted minimum
  one = Live.owns('role', roles.create(name: Live.name(klass, 'one'), type: 1))

  # create, refused: the name is taken
  refused(own: true) { roles.create(name: Live.name(klass, 'one'), type: 1) }

  # create, refused: type is required and the object's documented default does not apply
  refused(own: true) { roles.create(name: Live.name(klass, 'typeless')) }

  # create, refused: type outside 1, 2, 3
  refused(own: true) { roles.create(name: Live.name(klass, 'badtype'), type: 0) }

  # create, refused: readonly, which the role object reference marks read-only
  refused(own: true) { roles.create(name: Live.name(klass, 'readonly'), type: 1, readonly: 1) }

  # create, refused: a Super-admin-only UI element on a type 1 role
  refused(own: true) { roles.create(name: Live.name(klass, 'badui'), type: 1, rules: { 'ui' => [{ 'name' => 'administration.general', 'status' => 1 }] }) }

  # create with rules, accepted: a disabled UI element, a disabled action and an api deny list
  full = Live.owns('role', roles.create(name: Live.name(klass, 'full'), type: 1,
                                        rules: { 'ui' => [{ 'name' => 'monitoring.maps', 'status' => 0 }], 'ui.default_access' => 1,
                                                 'api.access' => 1, 'api.mode' => 0, 'api' => ['*.create', '*.update', '*.delete'],
                                                 'actions' => [{ 'name' => 'execute_scripts', 'status' => 0 }], 'actions.default_access' => 1,
                                                 'modules.default_access' => 0, 'services.read.mode' => 1, 'services.write.mode' => 0 }))

  # the reads
  roles.get_full_data(name: Live.name(klass, 'one'))
  roles.get_id(name: Live.name(klass, 'one'))
  roles.get_id(name: Live.name(klass, 'absent'))
  roles.dump_by_id(roleid: one)
  roles.dump_by_id(id: one)
  roles.get_raw(roleids: [one], selectUsers: 'extend')
  roles.all
  roles.get_ids_by_name(name: Live.name(klass, 'one'))
  roles.get_ids_by_name(name: Live.name(klass, 'absent'))

  # update, skipped: the payload already matches the dump, so only the dump goes out
  roles.update(roleid: Live::Interlock.safe('role', one), name: Live.name(klass, 'one'))

  # update, issued: two properties in one request
  roles.update(roleid: Live::Interlock.safe('role', one), name: Live.name(klass, 'renamed'), type: 2)

  # update, refused: readonly
  refused { roles.update(roleid: Live::Interlock.safe('role', one), readonly: 1) }

  # the stored rules, string-keyed as the server sent them
  stored_rules = roles.dump_by_id(roleid: full).first['rules']

  # update carrying a collection: dump_by_id asks for selectRules, so the dump can prove rules equal
  roles.update(roleid: Live::Interlock.safe('role', full), rules: stored_rules)

  # update, issued: one sub-property differs
  roles.update(roleid: Live::Interlock.safe('role', full), rules: { 'api.mode' => 1 })

  # rules(): one role.update carrying exactly roleid and rules, nothing read first
  rm = Live.owns('role', roles.create(name: Live.name(klass, 'rules-method'), type: 1,
                                      rules: { 'api.access' => 1, 'api.mode' => 1, 'api' => ['host.get'], 'modules.default_access' => 0 }))
  roles.rules(roleid: Live::Interlock.safe('role', rm), rules: { 'api.mode' => 0 })

  # rules(), refused: without a roleid the null goes out and the server refuses, not the gem
  refused { roles.rules(rules: { 'api.mode' => 0 }) }

  # the upserts, four branches
  roles.get_or_create(name: Live.name(klass, 'renamed'), type: 2)
  Live.owns('role', roles.get_or_create(name: Live.name(klass, 'goc'), type: 1))
  roles.create_or_update(name: Live.name(klass, 'goc'), type: 2)
  Live.owns('role', roles.create_or_update(name: Live.name(klass, 'cou'), type: 1))

  # the two writing aliases
  added = Live.owns('role', roles.add(name: Live.name(klass, 'added'), type: 1))
  roles.destroy(Live::Interlock.safe('role', added))
  Live.disown('role', added)

  # delete
  disposable = Live.owns('role', roles.create(name: Live.name(klass, 'disposable'), type: 1))
  roles.delete(Live::Interlock.safe('role', disposable))
  Live.disown('role', disposable)

  # delete, refused: a user holds the role, a refusal the role.delete reference does not document
  refused { roles.delete(Live::Interlock.safe('role', member)) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
