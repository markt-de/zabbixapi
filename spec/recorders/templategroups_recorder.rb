# Recorder for ZabbixApi::TemplateGroups: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/templategroups/crud.json.
#
# The order below is the order spec/zabbixapi/classes/templategroups_spec.rb indexes the file in:
# seven creates (the accepted minimum, four refusals, the bulk form and one carrying an explicit
# uuid), the eight reads, the three updates (skipped, issued, refused), the four upsert branches,
# the two writing aliases, a delete given a String id, and the delete a template's only group
# refuses. Not recorded: a forced update, which differs from the skipped one only in being issued
# and which the shared example group proves offline; the documented get parameters beyond one
# representative per return shape, which are server behaviour and belong to the acceptance spec.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/templategroups_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'securerandom'
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# A real UUIDv4 without its dashes, the form the server stores and the import format carries.
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

klass = 'templategroups'
templategroups = Live.session.templategroups

# Templates before groups: a group holding a template that belongs to it alone cannot be deleted.
Live.preclean(klass, 'template')
Live.preclean(klass, 'templategroup')

Live::Recorder.start!
begin
  # create: the accepted minimum, name alone
  one = Live.owns('templategroup', templategroups.create(name: Live.name(klass, 'one')))

  # create, refused: the name is taken
  refused { templategroups.create(name: Live.name(klass, 'one')) }

  # create, refused: name is required
  refused { templategroups.create(uuid: uuid4) }

  # create, refused: groupid, which the templategroup object reference marks read-only
  refused { templategroups.create(name: Live.name(klass, 'roid'), groupid: one) }

  # create, refused: 32 hex characters that are not a UUIDv4, a constraint the templategroup object
  # reference does not document
  refused { templategroups.create(name: Live.name(klass, 'baduuid'), uuid: 'abcdef0123456789abcdef0123456789') }

  # create: the documented bulk form, an Array of objects in one request, answered with one id each.
  # Every id is registered, because the call creates them all.
  templategroups.create([{ name: Live.name(klass, 'bulk1') }, { name: Live.name(klass, 'bulk2') }]).each { |id| Live.owns('templategroup', id) }

  # create: two properties in one call, the uuid written rather than minted
  Live.owns('templategroup', templategroups.create(name: Live.name(klass, 'two'), uuid: uuid4))

  # the reads
  templategroups.get_full_data(name: Live.name(klass, 'one'))
  templategroups.get_id(name: Live.name(klass, 'one'))
  templategroups.get_id(name: Live.name(klass, 'one'), groupid: one)
  templategroups.get_id(name: Live.name(klass, 'absent'))
  templategroups.dump_by_id(groupid: one)
  templategroups.get_raw(output: ['name'], groupids: [one])
  templategroups.get_raw(countOutput: true, groupids: [one])
  templategroups.all

  # update, skipped: the payload already matches the dump, so only the dump goes out
  templategroups.update(groupid: one, name: Live.name(klass, 'one'))

  # update, issued: two properties at once, and uuid is writable after creation
  templategroups.update(groupid: one, name: Live.name(klass, 'batched'), uuid: uuid4)

  # update, refused: the same malformed uuid as on create. A uuid rather than an empty name: were an
  # empty name accepted, the group would lose the prefix the pre-clean finds it by.
  refused { templategroups.update(groupid: one, uuid: 'abcdef0123456789abcdef0123456789') }

  # create_or_update, update branch: the name exists, the uuid differs
  templategroups.create_or_update(name: Live.name(klass, 'two'), uuid: uuid4)

  # create_or_update, create branch, then get_or_create on that same name, which finds it and
  # creates nothing
  Live.owns('templategroup', templategroups.create_or_update(name: Live.name(klass, 'three')))
  templategroups.get_or_create(name: Live.name(klass, 'three'))

  # get_or_create, create branch
  Live.owns('templategroup', templategroups.get_or_create(name: Live.name(klass, 'four')))

  # the two writing aliases, and the id type a delete echoes for an Integer
  added = Live.owns('templategroup', templategroups.add(name: Live.name(klass, 'added')))
  templategroups.destroy(added)
  Live.disown('templategroup', added)

  # delete given a String id, for the type the server echoes in that case
  disposable = Live.owns('templategroup', templategroups.create(name: Live.name(klass, 'disposable')))
  templategroups.delete(disposable.to_s)
  Live.disown('templategroup', disposable)

  # delete, refused: the group holds a template that belongs to no other group
  templated = Live.owns('templategroup', templategroups.create(name: Live.name(klass, 'templated')))
  Live.owns('template', Live.session.templates.create(host: Live.name(klass, 'tpl'), groups: [{ groupid: templated }]))
  refused { templategroups.delete(templated) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
  # The bulk create registers its own ids, so teardown reaches them; these calls are a defence
  # against a run that aborted before registering, and run after the file was written, so they
  # cannot reach the fixture.
  Live.preclean(klass, 'template')
  Live.preclean(klass, 'templategroup')
end
