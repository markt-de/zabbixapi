# Recorder for ZabbixApi::Mediatypes: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/mediatypes/crud.json.
#
# The order below is the order spec/zabbixapi/classes/mediatypes_spec.rb indexes the file in: two
# creates around one refusal, the eight reads, the seven updates (issued, skipped, forced, resolved
# from the name, resolved to nothing, a collection the dump cannot show, refused by the server), the
# four upsert branches, the two writing aliases, a create and its delete, and one refused delete.
#
# Deliberately not recorded: `all`, because its extend response carries every media type on the
# server, webhook scripts included - the shared group is fed the rows recorded here instead, and
# `all` over the real table is asserted live; the passwd case, server behaviour the recorder's scrub
# would hide, writing every passwd value as "<scrubbed>"; the transport requirements and the enum,
# range and gated-property refusals, all server behaviour that no branch of the gem depends on, one
# recorded refusal being enough to prove the error path offline.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/mediatypes_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# The minimum each transport needs before anything else can travel with it, which the mediatype
# object reference marks required: smtp_server and smtp_email for Email, exec_path for Script,
# script for Webhook. Every address points into the reserved .invalid domain, so nothing can be
# delivered anywhere.
EMAIL = { type: 0, smtp_server: 'smtp.example.invalid', smtp_email: 'zbxapi-spec@example.invalid' }.freeze
SCRIPT = { type: 1, exec_path: 'notify.sh' }.freeze
WEBHOOK = { type: 4, script: 'return 1;' }.freeze

# A refusal is one of the cases being recorded, so the exchange is what matters and the exception
# is not. Only ApiError is swallowed: a transport failure must still abort the run.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

klass = 'mediatypes'
mediatypes = Live.session.mediatypes
Live.preclean(klass, 'mediatype')

Live::Recorder.start!
begin
  mail_name = Live.name(klass, 'mail')
  absent_name = Live.name(klass, 'absent')

  # create: the accepted minimum of the Email transport
  mail = Live.owns('mediatype', mediatypes.create(EMAIL.merge(name: mail_name)))

  # create, refused: the name is taken
  refused { mediatypes.create(EMAIL.merge(name: mail_name)) }

  # create: a second transport, carrying a parameters collection
  Live.owns('mediatype', mediatypes.create(WEBHOOK.merge(name: Live.name(klass, 'hook'), parameters: [{ name: 'Message', value: '{ALERT.MESSAGE}' }])))

  # the reads
  mediatypes.get_full_data(name: mail_name)
  mediatypes.get_id(name: mail_name)
  # get_id with a second key beside the name: the override filters on the name alone
  mediatypes.get_id(name: mail_name, maxattempts: 99)
  mediatypes.get_id(name: absent_name)
  mediatypes.dump_by_id(mediatypeid: mail)
  mediatypes.get_raw(mediatypeids: [mail], selectMessageTemplates: 'extend')
  mediatypes.get_raw(output: ['name'], filter: { type: 4 })
  mediatypes.get_raw(countOutput: true, mediatypeids: [mail])

  # update, issued: the description differs from the dump
  mediatypes.update(mediatypeid: mail, description: 'first description')

  # update, skipped: the payload now matches the dump, so only the dump goes out
  mediatypes.update(mediatypeid: mail, description: 'first description')

  # update, forced: the same payload, issued regardless
  mediatypes.update({ mediatypeid: mail, description: 'first description' }, true)

  # update without an id: the override resolves it from the name
  mediatypes.update(name: mail_name, description: 'second description')

  # update by a name no media type carries: one lookup, then the local refusal
  refused { mediatypes.update(name: absent_name, description: 'third description') }

  # update carrying message_templates, which the dump does not carry: issued
  mediatypes.update(mediatypeid: mail, message_templates: [{ eventsource: 0, recovery: 0, subject: 'S', message: 'M' }])

  # update, refused by the server on the second request, the dump before it having succeeded
  refused { mediatypes.update(mediatypeid: mail, maxattempts: 101) }

  # get_or_create, found branch: the name exists, so nothing is created
  mediatypes.get_or_create(EMAIL.merge(name: mail_name))

  # get_or_create, create branch, on a third transport
  goc_name = Live.name(klass, 'goc')
  Live.owns('mediatype', mediatypes.get_or_create(SCRIPT.merge(name: goc_name)))

  # create_or_update, update branch: the name exists, the description differs
  mediatypes.create_or_update(name: goc_name, description: 'per upsert')

  # create_or_update, create branch
  Live.owns('mediatype', mediatypes.create_or_update(EMAIL.merge(name: Live.name(klass, 'cou'))))

  # the two writing aliases
  added = Live.owns('mediatype', mediatypes.add(EMAIL.merge(name: Live.name(klass, 'added'))))
  mediatypes.destroy(added)
  Live.disown('mediatype', added)

  # delete, and a delete of an id no media type carries
  disposable = Live.owns('mediatype', mediatypes.create(EMAIL.merge(name: Live.name(klass, 'disposable'))))
  mediatypes.delete(disposable)
  Live.disown('mediatype', disposable)
  refused { mediatypes.delete(999999999) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
  # These calls run after the file was written, so they cannot reach the fixture.
  Live.preclean(klass, 'mediatype')
end
