# Recorder for ZabbixApi::Drules: runs the cases below against the server ZABBIX_URL names, through
# the gem itself, and writes spec/fixtures/drules/crud.json.
#
# Safety: an enabled discovery rule starts discovering as soon as it is added, as the manual's
# Configuring a network discovery rule page states, and delay governs only the repeats, so every
# rule created here carries status 1 through disabled() and none is ever enabled - the gem's own
# default_options would arm it with status 0. Every address is RFC 5737 documentation space.
#
# The order below is the order spec/zabbixapi/classes/drules_spec.rb indexes the file in: eight
# creates (one accepted, six refused, one carrying every writable property but proxyid), seven
# reads, four updates each preceded by the dump Basic#update issues, the four upsert branches, the
# two writing aliases, a rule created and deleted by its String id, and one refused delete.
# Deliberately not recorded: a forced update, which differs from the skipped one only in being
# issued and which the shared example group proves offline; the iprange formats, the delay,
# concurrency_max and status values, the check types and their properties, and the further
# parameters the drule.get reference documents, which are server behaviour and belong to the
# acceptance spec.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/drules_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# Every rule this recorder creates is disabled, and no payload here passes a status of its own.
def disabled(payload)
  { status: 1 }.merge(payload)
end

# A TCP check on port 65001, enough to satisfy the required dchecks; the rule holding it never runs.
def tcp_check(extra = {})
  { type: 8, ports: '65001' }.merge(extra)
end

# A Zabbix agent check, a type that requires key_ and may carry uniq, unlike a TCP check.
def agent_check(extra = {})
  { type: 9, key_: 'system.uname', ports: '10050' }.merge(extra)
end

# A refusal is one of the cases being recorded, so the exchange is what matters and the exception is
# not. Only ApiError is swallowed: a transport failure must still abort the run.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

klass = 'drules'
drules = Live.session.drules

Live.preclean(klass, 'drule')

Live::Recorder.start!
begin
  # create: the accepted minimum through the wrapper, the five default_options around it
  one = Live.owns('drule', drules.create(disabled(name: Live.name(klass, 'one'), iprange: '192.0.2.10', dchecks: [tcp_check])))

  # create, refused: the name is taken
  refused { drules.create(disabled(name: Live.name(klass, 'one'), iprange: '192.0.2.11', dchecks: [tcp_check])) }

  # create, refused: the nil name default is dropped rather than sent as null, and the server
  # answers `Field "name" is mandatory.`
  refused { drules.create(disabled(iprange: '192.0.2.12', dchecks: [tcp_check])) }

  # create, refused: the nil iprange default is dropped too, and the server answers
  # `Incorrect value for field "iprange": cannot be empty.`
  refused { drules.create(disabled(name: Live.name(klass, 'noiprange'), dchecks: [tcp_check])) }

  # create, refused: dchecks is required and no default can stand in for it
  refused { drules.create(disabled(name: Live.name(klass, 'nochecks'), iprange: '192.0.2.13')) }

  # create, refused: an empty dchecks array is no checks either
  refused { drules.create(disabled(name: Live.name(klass, 'emptychecks'), iprange: '192.0.2.14', dchecks: [])) }

  # create, refused: error is read-only
  refused { drules.create(disabled(name: Live.name(klass, 'readonly'), iprange: '192.0.2.15', dchecks: [tcp_check], error: 'boom')) }

  # create: every writable property but proxyid in one call, the caller overriding three of the
  # defaults
  full = Live.owns('drule', drules.create(disabled(name: Live.name(klass, 'full'), iprange: '192.0.2.1-100, 198.51.100.0/24',
                                                   delay: '2h', concurrency_max: 7, dchecks: [tcp_check, agent_check(uniq: 1, host_source: 3)])))

  # the reads
  drules.get_full_data(name: Live.name(klass, 'one'))
  drules.get_id(name: Live.name(klass, 'one'))
  drules.get_id(name: Live.name(klass, 'absent'))
  drules.dump_by_id(druleid: one)
  drules.get_raw(output: %w[druleid name], druleids: [full], selectDChecks: 'extend')
  drules.get_raw(countOutput: true, druleids: [one])
  drules.all

  # update, skipped: the payload repeats the delay default_options forced, so only the dump goes out
  drules.update(druleid: one, delay: '3600')

  # update, issued: a scalar the dump carries
  drules.update(druleid: one, delay: '2h')

  # update, issued: dchecks are never in output extend, so the comparison cannot see them
  drules.update(druleid: one, dchecks: [agent_check])

  # update, refused: error is read-only on update too; forced, so no comparison can swallow it
  refused { drules.update({ druleid: one, error: 'boom' }, true) }

  # create_or_update, update branch: the name exists and the delay differs
  drules.create_or_update(disabled(name: Live.name(klass, 'one'), iprange: '192.0.2.10', delay: '30m', dchecks: [tcp_check]))

  # create_or_update, create branch, then get_or_create on that same name, which finds it and
  # creates nothing
  Live.owns('drule', drules.create_or_update(disabled(name: Live.name(klass, 'upserted'), iprange: '192.0.2.16', dchecks: [tcp_check])))
  drules.get_or_create(disabled(name: Live.name(klass, 'upserted'), iprange: '192.0.2.16', dchecks: [tcp_check]))

  # get_or_create, create branch
  Live.owns('drule', drules.get_or_create(disabled(name: Live.name(klass, 'gotten'), iprange: '192.0.2.17', dchecks: [tcp_check])))

  # the two writing aliases; destroy is given the Integer id create returned
  added = Live.owns('drule', drules.add(disabled(name: Live.name(klass, 'added'), iprange: '192.0.2.18', dchecks: [tcp_check])))
  drules.destroy(added)
  Live.disown('drule', added)

  # delete given a String id, for the type the server answers with in that case
  disposable = Live.owns('drule', drules.create(disabled(name: Live.name(klass, 'disposable'), iprange: '192.0.2.19', dchecks: [tcp_check])))
  drules.delete(disposable.to_s)
  Live.disown('drule', disposable)

  # delete, refused: an id no rule carries
  refused { drules.delete(999999999) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
