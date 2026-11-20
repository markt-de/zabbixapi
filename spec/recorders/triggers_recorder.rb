# Recorder for ZabbixApi::Triggers: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/triggers/crud.json.
#
# What the triggers below need to exist - a host group, two hosts and one trapper item each - is
# built before the recording starts, so the file carries trigger.* exchanges only and the unit spec
# can index them by position. The second host carries the twin, a trigger of base's description over
# its own item: it is what makes the unscoped get_id's refusal, and the hostid scoping of the scoped
# one and of the upserts, observable.
#
# The order below is the order the unit spec indexes the file in: seven creates (the minimum, the
# twin on the second host, one with ten optional properties and four refusals), six reads, four
# updates (issued, skipped, a collection the dump cannot prove, a read-only refusal), the three
# replace branches, the three upsert branches - create_or_update issuing a lookup, a dump and an
# update - the two dependency creates with the self-dependency refusal, and finally the two writing
# aliases, a disposable trigger deleted by String id and a refused delete. Not recorded: all, which
# would pull every trigger on the server into the fixture - the unit spec scripts its two rows
# instead; a forced update, which differs from the skipped one only in being issued and which the
# shared example group proves offline.
#
# Every trigger here is a last() over a trapper item and nothing is ever pushed to those items, so
# none of them can fire. Items and triggers are contents and are not registered for teardown: they
# go with their host.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/triggers_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# A refusal is a recorded exchange like any other, so each one is provoked deliberately and its
# exception dropped here.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

klass = 'triggers'
triggers = Live.session.triggers

# Hosts before groups: a group that is a host's only group cannot be deleted.
Live.preclean(klass, 'host')
Live.preclean(klass, 'hostgroup')

item_key = 'zbxapi.spec.triggers.value'
group = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'grp')))
host_names = [Live.name(klass, 'h1'), Live.name(klass, 'h2')]
host_ids = host_names.map do |host_name|
  hostid = Live.owns('host', Live.session.hosts.create(host: host_name, groups: [{ groupid: group }], description: 'spec fixture: no interface, one trapper item, nothing is ever pushed to it'))
  Live.session.items.create(name: "#{host_name}-trap", key_: item_key, hostid: hostid, type: 2, value_type: 3)
  hostid
end
expression = host_names.map { |host_name| "last(/#{host_name}/#{item_key})>0" }
base_name = Live.name(klass, 'base')

Live::Recorder.start!
begin
  # create: description and expression alone, which the trigger object reference requires on create
  base = triggers.create(description: base_name, expression: expression[0])

  # create: the same description on the second host, which the server allows
  triggers.create(description: base_name, expression: expression[1])

  # create, refused: that description and expression already exist on this host
  refused { triggers.create(description: base_name, expression: expression[0]) }

  # create: ten optional properties of one object, tags included
  triggers.create(description: Live.name(klass, 'full'), expression: expression[0], event_name: 'evt {HOST.NAME}', opdata: 'op', comments: 'recorded for the triggers fixture', priority: 5, status: 1, type: 1, url: 'http://example.invalid/', url_name: 'runbook', manual_close: 1, tags: [{ tag: 'zbxapi-spec', value: 'triggers' }])

  # create, refused: recovery_mode 1 without a recovery_expression
  refused { triggers.create(description: Live.name(klass, 'rm1'), expression: expression[0], recovery_mode: 1) }

  # create, refused: a priority above the documented 0-5
  refused { triggers.create(description: Live.name(klass, 'pri'), expression: expression[0], priority: 6) }

  # create, refused: hostid, which the trigger object reference does not list
  refused { triggers.create(description: Live.name(klass, 'scoped'), expression: expression[0], hostid: host_ids[0]) }

  # the reads
  triggers.get_full_data(description: base_name)                  # both hosts' triggers
  triggers.get_id(description: base_name, hostid: host_ids[0])    # scoped: narrows to the first host
  # unscoped: two hosts carry the description, so one_id! refuses after the exchange is recorded
  begin
    triggers.get_id(description: base_name)
  rescue ZabbixApi::ApiError
    nil
  end
  triggers.get_id(description: Live.name(klass, 'absent'))        # nothing
  triggers.dump_by_id(triggerid: base)                            # expandExpression, items, functions
  triggers.get_raw(triggerids: [base], output: %w[triggerid description expression], expandExpression: true)

  # update, issued: the dump differs
  triggers.update(triggerid: base, comments: 'recorded update')

  # update, skipped: the dump already carries that comment, so only the dump goes out
  triggers.update(triggerid: base, comments: 'recorded update')

  # update, issued although the dump shows no difference: the dump carries no tags
  triggers.update(triggerid: base, tags: [{ tag: 'zbxapi-spec', value: 'triggers' }])

  # update, refused: templateid, which the trigger object reference marks read-only
  refused { triggers.update(triggerid: base, templateid: 999999) }

  # replace, unchanged: every supplied field matches, so neither delete nor create goes out
  safe = triggers.create(description: Live.name(klass, 'safe'), expression: expression[0], priority: 2)
  triggers.replace(triggerid: safe, description: Live.name(klass, 'safe'), expression: expression[0], priority: 2)

  # replace, changed: the old trigger is deleted first, then a new one is created
  triggers.replace(triggerid: safe, description: Live.name(klass, 'safe2'), expression: expression[0], priority: 2)

  # replace on a trigger that does not exist: refused after the dump, before any write
  refused { triggers.replace(triggerid: 999999999, description: Live.name(klass, 'safe3'), expression: expression[0]) }

  # get_or_create, found: description plus hostid finds base on the first host
  triggers.get_or_create(description: base_name, expression: expression[0], hostid: host_ids[0])

  # get_or_create, created: the hostid scopes the lookup and never reaches the create
  triggers.get_or_create(description: Live.name(klass, 'goc'), expression: expression[0], hostid: host_ids[0])

  # create_or_update, which updates in place: the priority below lands on the existing trigger, and
  # the lookup, dump and update are all recorded
  triggers.create_or_update(description: base_name, expression: expression[0], hostid: host_ids[0], priority: 5)

  # dependencies travel with the create; a self-dependency is refused on update
  dep = triggers.create(description: Live.name(klass, 'dep'), expression: expression[1])
  withdep = triggers.create(description: Live.name(klass, 'withdep'), expression: expression[0], dependencies: [{ triggerid: dep }])
  refused { triggers.update(triggerid: withdep, dependencies: [{ triggerid: withdep }]) }

  # the two writing aliases, and the id type a delete answers for an Integer
  added = triggers.add(description: Live.name(klass, 'added'), expression: expression[0])
  triggers.destroy(added)

  # delete with a String id, for the type the server answers in that case
  disposable = triggers.create(description: Live.name(klass, 'disposable'), expression: expression[0])
  triggers.delete(disposable.to_s)

  # delete, refused: no trigger carries that id
  refused { triggers.delete(999999999) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
