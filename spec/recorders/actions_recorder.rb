# Recorder for ZabbixApi::Actions: runs the cases below against the server ZABBIX_URL names, through
# the gem itself, and writes spec/fixtures/actions/crud.json.
#
# The order below is the order spec/zabbixapi/classes/actions_spec.rb indexes the file in: eleven
# creates (one accepted trigger action, nine refusals, one accepted discovery action), the eight
# reads, four updates (skipped, issued, collection, refused), the four upsert branches, the two
# writing aliases, a delete and the refusal of an id no action carries.
# Deliberately not recorded: a forced update, which differs from the skipped one only in being
# issued and which the shared example group proves offline; the condition-type and operation-type
# matrices, which are server behaviour - except the two operation refusals below, recorded for the
# wording the acceptance spec matches.
#
# Every action created here carries status: 1. The API default is 0, enabled, and an enabled action
# acts on real events at once, so no action here is ever created or updated into the enabled state,
# and neither the status default nor status 0 is recorded.
#
# The host group, media type and user group that the operations point at are created before the
# recording starts, so the fixture holds action.* exchanges only. They go through get_or_create,
# which the user group needs because it is not a container the live layer may pre-clean by name: a
# crashed run must not block the next one.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/actions_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# A refusal is one of the cases being recorded, so the exchange is what matters and the exception
# is not. Only ApiError is swallowed: a transport failure must still abort the run.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

klass = 'actions'
actions = Live.session.actions

# Actions first: one that references a host group blocks that group's deletion.
Live.preclean(klass, 'action')
Live.preclean(klass, 'mediatype')
Live.preclean(klass, 'hostgroup')

group = Live.owns('hostgroup', Live.session.hostgroups.get_or_create(name: Live.name(klass, 'hg')))
mediatype = Live.owns('mediatype', Live.session.mediatypes.get_or_create(name: Live.name(klass, 'mt'), type: 0, smtp_server: 'smtp.example.invalid', smtp_email: 'zbxapi-spec@example.invalid'))
usergroup = Live.owns('usergroup', Live.session.usergroups.get_or_create(name: Live.name(klass, 'ug')))

message_op = { operationtype: 0, opmessage: { default_msg: 1, mediatypeid: mediatype }, opmessage_grp: [{ usrgrpid: usergroup }] }
group_op = { operationtype: 4, opgroup: [{ groupid: group }] }
trigger_action = { eventsource: 0, status: 1, esc_period: '1h', operations: [message_op] }

Live::Recorder.start!
begin
  # create: a trigger action with one send-message operation
  one = Live.owns('action', actions.create(trigger_action.merge(name: Live.name(klass, 'one'))))

  # create, refused: the name is taken
  refused { actions.create(trigger_action.merge(name: Live.name(klass, 'one'))) }

  # create, refused: name is required
  refused { actions.create(trigger_action) }

  # create, refused: an action without a single operation
  refused { actions.create(name: Live.name(klass, 'noops'), eventsource: 0, status: 1, esc_period: '1h') }

  # create, refused: a send-message operation naming neither a user group nor a user
  refused { actions.create(trigger_action.merge(name: Live.name(klass, 'nodest'), operations: [{ operationtype: 0, opmessage: { default_msg: 1, mediatypeid: mediatype } }])) }

  # create, refused: the add-to-host-group operation on a trigger action
  refused { actions.create(trigger_action.merge(name: Live.name(klass, 'optrig4'), operations: [group_op])) }

  # create, refused: actionid is read-only
  refused { actions.create(trigger_action.merge(name: Live.name(klass, 'withid'), actionid: 99)) }

  # create, refused: eventsource outside the documented enum
  refused { actions.create(trigger_action.merge(name: Live.name(klass, 'badsource'), eventsource: 5)) }

  # create, refused: esc_period is gated on eventsource and rejected outright on a discovery action
  refused { actions.create(name: Live.name(klass, 'escdisc'), eventsource: 1, status: 1, esc_period: '1h', operations: [group_op]) }

  # create, refused: esc_period below the documented 60 s minimum
  refused { actions.create(trigger_action.merge(name: Live.name(klass, 'escmin'), esc_period: '30s')) }

  # create: a discovery action, the second event source, with the add-to-host-group operation
  Live.owns('action', actions.create(name: Live.name(klass, 'discovery'), eventsource: 1, status: 1, operations: [group_op]))

  # the reads
  actions.get_full_data(name: Live.name(klass, 'one'))
  # the read naming nothing: the filter is dropped whole rather than sent with a null name, so every
  # action comes back with all four selects - the unfiltered table the unit spec replays
  actions.get_full_data({})
  actions.get_id(name: Live.name(klass, 'one'))
  actions.get_id(name: Live.name(klass, 'absent'))
  actions.dump_by_id(actionid: one)
  actions.get_raw(output: ['name'], usrgrpids: [usergroup])
  actions.get_raw(countOutput: true, actionids: [one])
  actions.all

  # update, skipped: the payload already matches the dump, so only the dump goes out
  actions.update(actionid: one, status: 1)

  # update, issued: a scalar property the dump carries
  actions.update(actionid: one, esc_period: '2h')

  # update, issued although the operation is the stored one: the output: extend dump lacks
  # operations, so the call goes out
  actions.update(actionid: one, operations: [message_op])

  # update, refused: eventsource is constant, and the dump before it succeeded
  refused { actions.update(actionid: one, eventsource: 1) }

  # create_or_update, update branch: the name exists, the escalation period differs
  actions.create_or_update(name: Live.name(klass, 'one'), esc_period: '3h')

  # create_or_update, create branch
  Live.owns('action', actions.create_or_update(trigger_action.merge(name: Live.name(klass, 'upserted'))))

  # get_or_create on a name that exists, which creates nothing
  actions.get_or_create(trigger_action.merge(name: Live.name(klass, 'one')))

  # get_or_create, create branch
  Live.owns('action', actions.get_or_create(trigger_action.merge(name: Live.name(klass, 'gotten'))))

  # the two writing aliases
  added = Live.owns('action', actions.add(trigger_action.merge(name: Live.name(klass, 'added'))))
  actions.destroy(added)
  Live.disown('action', added)

  # delete, and the refusal of an id no action carries
  disposable = Live.owns('action', actions.create(trigger_action.merge(name: Live.name(klass, 'disposable'))))
  actions.delete(disposable)
  Live.disown('action', disposable)
  refused { actions.delete(999999999) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
