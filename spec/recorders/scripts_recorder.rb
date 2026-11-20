# Recorder for ZabbixApi::Scripts: runs the cases below against the server ZABBIX_URL names, through
# the gem itself, and writes spec/fixtures/scripts/crud.json, spec/fixtures/scripts/execute.json and
# spec/fixtures/scripts/byevents.json.
#
# Three scenarios, because the class has three surfaces with different fixtures: crud needs nothing
# but a host group, execute needs an interface-less host of its own plus one script per outcome,
# byevents needs an event - and this run owns none, so it reads the standing problem.
# Recorder.start! clears the buffer, so each scenario starts empty and the earlier files are already
# on disk when the riskier halves begin.
#
# The order below is the order the unit spec indexes the files in. crud: one accepted create and
# four refusals, a webhook with a parameter, the duplicate (name, menu_path) pair, the seven reads,
# three skipped updates, two issued ones and the read-back of the second, the four upsert branches,
# the two writing aliases, the delete and scope-change refusals an action operation causes, and two
# more deletes. execute: three accepted executions, eight refusals and six getscriptsbyhost calls -
# its own fixtures and the configuration-cache wait are built before the buffer is cleared and are
# therefore not in that file. byevents: five getscriptsbyevents calls alone - its script and the
# three reads that resolve the standing problem are built before the buffer is cleared too.
#
# Not recorded: a forced update, which differs from the skipped one only in being issued and which
# the shared example group proves offline; script.execute against an event, because this run owns no
# event and the standing problem is only ever read; execute_on 0, which against a host no agent
# polls hangs until the HTTP timeout.
#
# Safety: every scope 2 script carries the groupid of a host group this run created, every execute
# targets this run's own interface-less host, and the only bodies that run are a printf with a
# literal and a webhook returning a literal. Nothing writes, sleeps, forks or opens a socket; no
# stock script is executed; the one action created is disabled and filtered onto this run's own
# empty host group.
#
# The one deliberate exception is the byevents scenario's scope 4 script: a script scoped to a host
# group is offered for an event only when the event's host is in that group, so it carries the group
# of the standing problem's host rather than one this run created. It is a webhook returning a
# literal, it is never executed here, and it goes away with the teardown; the standing problem
# itself is read and never written.
#
# Live.retrying wraps nothing but single-request calls, because a retry re-issues every request
# its block made: a gem call that sends two requests and meets a transient on the second records
# the first twice. Inside the recording those are the raw action create and delete of the crud
# scenario, one request each, so a transient there is retried and recorded once. On any other
# recorded call the recorder's hook raises a transient as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, it passes the refusal rescues: the run aborts and
# the ensure tears down.
#
# script and action are in Live::CONTAINERS, so the run pre-cleans all four containers it creates,
# the referencing object before the one it names: an action operation blocks its script's delete,
# and a host group's delete is refused while an action or a script references it or a host belongs
# to it alone. The order is therefore action, script, host, hostgroup. A script or action the
# pre-clean could not remove is reported and stops the run, rather than recording a fixture whose
# creates collide with a leftover name.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/scripts_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the files to /tmp instead and prints their paths.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# Every refusal below is recorded on purpose: the unit spec replays it as an ApiError.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

klass = 'scripts'
scripts = Live.session.scripts

server_command = %q(printf 'zbxapi\n')
input_command = %q(printf '%s\n' '{MANUALINPUT}')
webhook_code = "Zabbix.log(3, '[zbxapi-spec] webhook probe');\nreturn 'zbxapi';"
missing = 999999999

Live.preclean(klass, 'action')
Live.preclean(klass, 'script')
Live.preclean(klass, 'host')
Live.preclean(klass, 'hostgroup')

[%w[script name], %w[action name]].each do |object, field|
  left = Live.raw("#{object}.get", output: [field], search: { field.to_sym => Live.prefix(klass) })
  abort("#{left.size} leftover #{object} object(s) under #{Live.prefix(klass)}: #{left.map { |row| row[field] }.join(', ')}") unless left.empty?
end

Live::Recorder.start!
begin
  # Every scope 2 script of this scenario is scoped to this group, so none of them is offered on a
  # real host.
  group = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'hg')))

  # create: accepted with name, scope, type and command, the properties a type 0 script requires
  one = Live.owns('script', scripts.create(name: Live.name(klass, 'one'), scope: 1, type: 0, command: server_command))

  # create, refused: the name is taken at the same menu_path
  refused { scripts.create(name: Live.name(klass, 'one'), scope: 1, type: 0, command: server_command) }

  # create, refused: scriptid is read-only
  refused { scripts.create(name: Live.name(klass, 'readonly'), scope: 1, type: 0, command: server_command, scriptid: missing) }

  # create, refused: 4 is the hole in the type enum
  refused { scripts.create(name: Live.name(klass, 'type4'), scope: 1, type: 4, command: server_command) }

  # create, refused: menu_path is gated to scopes 2 and 4 and must be empty outside them
  refused { scripts.create(name: Live.name(klass, 'menu'), scope: 1, type: 0, command: server_command, menu_path: 'zbxapi-spec/deep') }

  # create: a webhook with one parameter, for the parameters read-back and the type 5 to 0 clearing
  webhook = Live.owns('script', scripts.create(name: Live.name(klass, 'webhook'), scope: 1, type: 5, command: webhook_code, timeout: '45s', parameters: [{ name: 'token', value: '{$ZBXAPI_SPEC}' }]))

  # create: one name under two menu paths, because a script is unique per (name, menu_path)
  Live.owns('script', scripts.create(name: Live.name(klass, 'dup'), scope: 2, type: 0, command: server_command, groupid: group, menu_path: 'zbxapi-spec/a'))
  Live.owns('script', scripts.create(name: Live.name(klass, 'dup'), scope: 2, type: 0, command: server_command, groupid: group, menu_path: 'zbxapi-spec/b'))

  # the reads
  scripts.get_full_data(name: Live.name(klass, 'one'))
  scripts.get_id(name: Live.name(klass, 'one'))
  scripts.get_id(name: Live.name(klass, 'absent'))
  # one name under two menu paths, so one_id! refuses after the exchange is recorded
  refused { scripts.get_id(name: Live.name(klass, 'dup')) }
  scripts.dump_by_id(scriptid: one)
  scripts.get_raw(output: ['name'], scriptids: [one])
  scripts.all

  # update, skipped: the payload already matches the dump, so only the dump goes out
  scripts.update(scriptid: one, name: Live.name(klass, 'one'))

  # update, skipped although it names a collection: script.get extend returns parameters
  scripts.update(scriptid: one, parameters: [])
  scripts.update(scriptid: webhook, parameters: [{ name: 'token', value: '{$ZBXAPI_SPEC}' }])

  # update, issued
  scripts.update(scriptid: one, description: 'zbxapi-spec after')

  # update, issued: changing the type away from 5 clears parameters, as the script.update reference
  # says
  scripts.update(scriptid: webhook, type: 0, command: server_command)
  scripts.dump_by_id(scriptid: webhook)

  # create_or_update, update branch: the name exists and the description differs
  scripts.create_or_update(name: Live.name(klass, 'one'), scope: 1, type: 0, command: server_command, description: 'zbxapi-spec upserted')

  # create_or_update, create branch, then get_or_create on that same name, which creates nothing
  Live.owns('script', scripts.create_or_update(name: Live.name(klass, 'three'), scope: 1, type: 0, command: server_command))
  scripts.get_or_create(name: Live.name(klass, 'three'), scope: 1, type: 0, command: server_command)

  # get_or_create, create branch
  Live.owns('script', scripts.get_or_create(name: Live.name(klass, 'four'), scope: 1, type: 0, command: server_command))

  # the two writing aliases
  added = Live.owns('script', scripts.add(name: Live.name(klass, 'added'), scope: 1, type: 0, command: server_command))
  scripts.destroy(added)
  Live.disown('script', added)

  # delete and update, refused: an action operation references the script. The action is disabled and
  # its only condition names this run's own empty host group, so it can never fire.
  operation = Live.owns('script', scripts.create(name: Live.name(klass, 'operation'), scope: 1, type: 0, command: server_command))
  action_params = {
    name: Live.name(klass, 'action'), eventsource: 0, status: 1, esc_period: '1h',
    filter: { evaltype: 0, conditions: [{ conditiontype: 0, operator: 0, value: group.to_s }] },
    operations: [{ operationtype: 1, opcommand: { scriptid: operation }, opcommand_hst: [{ hostid: 0 }] }]
  }
  action = Live.owns('action', Live.raw('action.create', action_params)['actionids'][0].to_i)
  refused { scripts.delete(operation) }
  refused { scripts.update({ scriptid: operation, scope: 2, groupid: group }, true) }
  Live.raw('action.delete', [action])
  Live.disown('action', action)

  # delete: once the action is gone the same call succeeds
  scripts.delete(operation)
  Live.disown('script', operation)

  # delete, refused: no script carries that id
  refused { scripts.delete(missing) }

  Live::Recorder.write(klass, 'crud')

  # The execute surface. Its fixtures are built before the buffer is cleared, so the second file
  # holds the executions and the getscriptsbyhost calls alone.
  own_group = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'exec-hg')))
  other_group = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'other-hg')))
  # No interface, no template, no item: there is no address for the server to connect to, which is
  # what makes the SSH refusal safe to provoke.
  target = Live.owns('host', Live.session.hosts.create(host: Live.name(klass, 'target'), groups: [{ groupid: own_group }]))

  runnable = Live.owns('script', scripts.create(name: Live.name(klass, 'x-webhook'), scope: 2, type: 5, command: webhook_code, timeout: '10s', groupid: own_group))
  shell = Live.owns('script', scripts.create(name: Live.name(klass, 'x-shell'), scope: 2, type: 0, execute_on: 1, command: server_command, groupid: own_group))
  prompt = Live.owns('script', scripts.create(name: Live.name(klass, 'x-prompt'), scope: 2, type: 0, execute_on: 1, command: input_command, groupid: own_group,
                                              confirmation: 'run with {MANUALINPUT}?', manualinput: 1, manualinput_prompt: 'value?',
                                              manualinput_validator: '^[a-z]+$', manualinput_validator_type: 0, manualinput_default_value: 'zbxapi'))
  url = Live.owns('script', scripts.create(name: Live.name(klass, 'x-url'), scope: 2, type: 6, url: 'http://127.0.0.1/zbxapi-spec', groupid: own_group))
  ssh = Live.owns('script', scripts.create(name: Live.name(klass, 'x-ssh'), scope: 2, type: 2, command: server_command, username: 'zbxapi-spec', password: 'zbxapi-spec-secret', port: '2222', groupid: own_group))
  action_scope = Live.owns('script', scripts.create(name: Live.name(klass, 'x-action'), scope: 1, type: 0, command: server_command))
  foreign = Live.owns('script', scripts.create(name: Live.name(klass, 'x-foreign'), scope: 2, type: 5, command: webhook_code, timeout: '10s', groupid: other_group))

  # script.execute is answered by the Zabbix server, not by the frontend, so a host the API created
  # a moment ago answers "Unknown host identifier." until the server's configuration cache has
  # caught up. The probe is the real call and must not reach the fixture, so it runs before start!.
  Live.wait('the server configuration cache to know the target host', max: 180, step: 5) do
    scripts.execute(scriptid: runnable, hostid: target)
    true
  rescue ZabbixApi::ApiError => e
    raise unless e.message.include?('Unknown host identifier')

    false
  end

  Live::Recorder.start!

  # execute: a webhook, and its debug object
  scripts.execute(scriptid: runnable, hostid: target)

  # execute: a printf run on the Zabbix server, and its debug array
  scripts.execute(scriptid: shell, hostid: target)

  # execute: {MANUALINPUT} substituted, then a value the regexp validator rejects
  scripts.execute(scriptid: prompt, hostid: target, manualinput: 'zbxapi')
  refused { scripts.execute(scriptid: prompt, hostid: target, manualinput: '123') }

  # execute, refused: a URL script is not executable, as the script.execute reference says
  refused { scripts.execute(scriptid: url, hostid: target) }

  # execute, refused: an action-operation script is not executable either
  refused { scripts.execute(scriptid: action_scope, hostid: target) }

  # execute, refused: SSH against a host with no interface has no address to reach
  refused { scripts.execute(scriptid: ssh, hostid: target) }

  # execute, refused: the script is scoped to a group the target is not in
  refused { scripts.execute(scriptid: foreign, hostid: target) }

  # execute, refused: no scriptid - compact_params sends the hostid alone and the server objects
  refused { scripts.execute(hostid: target) }

  # execute, refused: neither hostid nor eventid
  refused { scripts.execute(scriptid: runnable) }

  # execute, refused: no script carries that id
  refused { scripts.execute(scriptid: missing, hostid: target) }

  # getscriptsbyhost: the object form, the array form, a scriptid narrowing it, manualinput expanded
  scripts.getscriptsbyhost(hostid: target)
  scripts.getscriptsbyhost([{ hostid: target }])
  scripts.getscriptsbyhost(hostid: target, scriptid: runnable)
  scripts.getscriptsbyhost(hostid: target, scriptid: prompt, manualinput: 'zbxapi')

  # getscriptsbyhost, refused: a bare array of ids
  refused { scripts.getscriptsbyhost([target]) }

  # getscriptsbyhost: an empty object, without the hostid the script.getscriptsbyhosts reference
  # requires
  scripts.getscriptsbyhost({})

  Live::Recorder.write(klass, 'execute')

  # The event surface. getscriptsbyevents answers which scripts an event offers, so it needs an
  # event, and this run owns none: it reads the standing problem and never writes it. A script
  # scoped to a host group is offered for an event only when the event's host is in that group, so
  # the script below carries that host's group rather than one of this run's.
  standing_host = Live.one('host', filter: { host: Live::STANDING_PROBLEM_HOST }, output: %w[hostid host])
  raise "the stock host #{Live::STANDING_PROBLEM_HOST}, which carries the standing problem, is not on this server" if standing_host.nil?

  standing_hostid = standing_host['hostid'].to_i
  standing = Live.one('problem', hostids: [standing_hostid], output: %w[eventid name])
  raise "no problem stands on #{Live::STANDING_PROBLEM_HOST}; this scenario has no event without one" if standing.nil?

  eventid = standing['eventid'].to_i
  event_group = Live.one('host', hostids: [standing_hostid], selectHostGroups: %w[groupid name])['hostgroups'].first['groupid'].to_i
  by_event = Live.owns('script', scripts.create(name: Live.name(klass, 'x-event'), scope: 4, type: 5, command: webhook_code, timeout: '10s', groupid: event_group))

  Live::Recorder.start!

  # getscriptsbyevents: the object form, the array form, a scriptid narrowing it
  scripts.getscriptsbyevents(eventid: eventid)
  scripts.getscriptsbyevents([{ eventid: eventid }])
  scripts.getscriptsbyevents(eventid: eventid, scriptid: by_event)

  # getscriptsbyevents, refused: a bare array of ids
  refused { scripts.getscriptsbyevents([eventid]) }

  # getscriptsbyevents with an empty object, recorded for whatever it answers: an empty Array, where
  # the script.getscriptsbyevents reference promises an object
  refused { scripts.getscriptsbyevents({}) }

  Live::Recorder.write(klass, 'byevents')
ensure
  Live.teardown
end
