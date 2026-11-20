# Recorder for ZabbixApi::HostGroups: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/hostgroups/crud.json.
#
# The order below is the order spec/zabbixapi/classes/hostgroups_spec.rb indexes the file in: seven
# creates (one accepted minimum, four refusals, one bulk create of two groups, one carrying an
# explicit uuid), the eight reads, the three updates (skipped, issued, refused), the four upsert
# branches, the two writing aliases, a delete given a String id, and the delete a host's only group
# refuses. Deliberately not recorded: a forced update, which differs from the skipped one only in
# being issued and which the shared example group proves offline; the remaining documented get
# parameters, which are server behaviour and belong to the acceptance spec.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/hostgroups_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'securerandom'
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# The server demands a UUIDv4 where the hostgroup object reference documents no format at all, so a
# real v4 without its dashes is the only value that exercises the property.
def uuid4
  SecureRandom.uuid.delete('-')
end

# A refusal is one of the cases being recorded, so the exchange is what matters and the exception
# is not. Only ApiError is swallowed: a transport failure must still abort the run.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

klass = 'hostgroups'
hostgroups = Live.session.hostgroups

# Hosts before groups: a group that is a host's only group cannot be deleted.
Live.preclean(klass, 'host')
Live.preclean(klass, 'hostgroup')

Live::Recorder.start!
begin
  # create: the accepted minimum, name alone
  one = Live.owns('hostgroup', hostgroups.create(name: Live.name(klass, 'one')))

  # create, refused: the name is taken
  refused { hostgroups.create(name: Live.name(klass, 'one')) }

  # create, refused: name is required
  refused { hostgroups.create(uuid: uuid4) }

  # create, refused: flags is read-only
  refused { hostgroups.create(name: Live.name(klass, 'flags'), flags: 4) }

  # create, refused: 32 hex characters that are not a UUIDv4
  refused { hostgroups.create(name: Live.name(klass, 'baduuid'), uuid: 'abcdef0123456789abcdef0123456789') }

  # create: the documented bulk form, an Array of two objects in one request, answered with both ids
  hostgroups.create([{ name: Live.name(klass, 'bulk1') }, { name: Live.name(klass, 'bulk2') }]).each { |id| Live.owns('hostgroup', id) }

  # create: two properties in one call, the uuid written rather than minted
  Live.owns('hostgroup', hostgroups.create(name: Live.name(klass, 'two'), uuid: uuid4))

  # the reads
  hostgroups.get_full_data(name: Live.name(klass, 'one'))
  hostgroups.get_id(name: Live.name(klass, 'one'))
  hostgroups.get_id(name: Live.name(klass, 'one'), groupid: one)
  hostgroups.get_id(name: Live.name(klass, 'absent'))
  hostgroups.dump_by_id(groupid: one)
  hostgroups.get_raw(output: ['name'], groupids: [one])
  hostgroups.get_raw(countOutput: true, groupids: [one])
  hostgroups.all

  # update, skipped: the payload already matches the dump, so only the dump goes out
  hostgroups.update(groupid: one, name: Live.name(klass, 'one'))

  # update, issued: two properties at once, and uuid is writable after creation
  hostgroups.update(groupid: one, name: Live.name(klass, 'batched'), uuid: uuid4)

  # update, refused: flags is read-only here too
  refused { hostgroups.update(groupid: one, flags: 4) }

  # create_or_update, update branch: the name exists, the uuid differs
  hostgroups.create_or_update(name: Live.name(klass, 'two'), uuid: uuid4)

  # create_or_update, create branch, then get_or_create on that same name, which creates nothing
  Live.owns('hostgroup', hostgroups.create_or_update(name: Live.name(klass, 'three')))
  hostgroups.get_or_create(name: Live.name(klass, 'three'))

  # get_or_create, create branch
  Live.owns('hostgroup', hostgroups.get_or_create(name: Live.name(klass, 'four')))

  # the two writing aliases; destroy is given an Integer id
  added = Live.owns('hostgroup', hostgroups.add(name: Live.name(klass, 'added')))
  hostgroups.destroy(added)
  Live.disown('hostgroup', added)

  # delete given a String id, for the type the server echoes back in that case
  disposable = Live.owns('hostgroup', hostgroups.create(name: Live.name(klass, 'disposable')))
  hostgroups.delete(disposable.to_s)
  Live.disown('hostgroup', disposable)

  # delete, refused: the group is the only one of a host
  hosted = Live.owns('hostgroup', hostgroups.create(name: Live.name(klass, 'hosted')))
  Live.owns('host', Live.session.hosts.create(host: Live.name(klass, 'host'), groups: [{ groupid: hosted }], status: 1))
  refused { hostgroups.delete(hosted) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
  # The pre-clean catches what a run created but aborted before registering, and runs after the file
  # was written, so it cannot reach the fixture.
  Live.preclean(klass, 'host')
  Live.preclean(klass, 'hostgroup')
end
