# Recorder for ZabbixApi::Maintenance: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/maintenance/crud.json.
#
# The order below is the order spec/zabbixapi/classes/maintenance_spec.rb indexes the file in: the
# accepted minimal create and six refusals, one rich create carrying all four collections at once,
# the six reads, the skipped update, the issued one, the one issued for a collection, the refused
# one, the four upsert branches, the two writing aliases, a delete by String id and one the server
# refuses.
#
# Not recorded: the two host groups and the host the maintenances hang on, created before the hook
# is installed so that the fixture holds maintenance calls only; a forced update, which differs from
# the skipped one only in being issued and which the shared example group proves offline; the
# deprecated groupids and hostids, a passthrough with nothing gem-side to assert, groupids asserted
# on the server by the acceptance spec.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/maintenance_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# A refusal is a recorded exchange, not an abort.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

klass = 'maintenance'
maintenance = Live.session.maintenance

# Maintenances first: a host group that is the only group of a maintenance cannot be deleted, and a
# host group that is a host's only one cannot either.
Live.preclean(klass, 'maintenance')
Live.preclean(klass, 'host')
Live.preclean(klass, 'hostgroup')

hg1 = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'hg1')))
hg2 = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'hg2')))
h1 = Live.owns('host', Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: hg1 }]))

# active_since, active_till and period are stored to the minute, so every timestamp here is
# minute-aligned already and a read-back needs no rounding.
since = ((Time.now.to_i / 60) * 60) - 3600
till = since + 86_400
one_time = { timeperiod_type: 0, period: 3600, start_date: since }
base = { name: Live.name(klass, 'one'), active_since: since, active_till: till, groups: [{ groupid: hg1 }], timeperiods: [one_time] }

Live::Recorder.start!
begin
  one = Live.owns('maintenance', maintenance.create(base))

  refused { maintenance.create(base) }                                                                                                  # the name is taken
  refused { maintenance.create(base.except(:timeperiods)) }                                                                             # a required parameter missing
  refused { maintenance.create(base.merge(name: Live.name(klass, 'nogroup'), groups: [], hosts: [])) }                                   # two empty arrays satisfy neither
  refused { maintenance.create(base.merge(name: Live.name(klass, 'tphole'), timeperiods: [{ timeperiod_type: 1, period: 3600 }])) }      # the hole in the enum
  refused { maintenance.create(base.merge(name: Live.name(klass, 'sttot'), timeperiods: [one_time.merge(start_time: 0)])) }              # a gated property at its own default
  refused { maintenance.create(base.merge(name: Live.name(klass, 'withid'), maintenanceid: 99)) }                                        # read-only on create

  # One object carrying every collection a maintenance takes, and one time period of each type.
  everything = {
    name: Live.name(klass, 'rich'),
    description: 'every collection at once',
    active_since: since,
    active_till: till,
    maintenance_type: 0,
    tags_evaltype: 2,
    groups: [{ groupid: hg1 }, { groupid: hg2 }],
    hosts: [{ hostid: h1 }],
    tags: [{ tag: 'service', operator: 0, value: 'mysqld' }, { tag: 'error', operator: 2, value: '' }],
    timeperiods: [one_time,
                  { timeperiod_type: 2, period: 3600, start_time: 3600, every: 1 },
                  { timeperiod_type: 3, period: 3600, start_time: 3600, every: 1, dayofweek: 64 },
                  { timeperiod_type: 4, period: 3600, start_time: 3600, every: 1, dayofweek: 64, month: 1 }]
  }
  rich = Live.owns('maintenance', maintenance.create(everything))

  # the reads
  maintenance.get_full_data(name: Live.name(klass, 'one'))
  maintenance.get_id(name: Live.name(klass, 'one'))
  maintenance.get_id(name: Live.name(klass, 'absent'))
  maintenance.dump_by_id(maintenanceid: one)
  maintenance.get_raw(maintenanceids: [rich], selectHostGroups: 'extend', selectHosts: 'extend', selectTags: 'extend', selectTimeperiods: 'extend')
  maintenance.all

  # update, skipped: the payload already matches the dump, so only the dump goes out
  maintenance.update(maintenanceid: one, name: Live.name(klass, 'one'))

  # update, issued: a scalar the dump carries and that differs
  maintenance.update(maintenanceid: one, description: 'erste')

  # update, issued: groups, which the output extend dump lacks, so the call goes out
  maintenance.update(maintenanceid: one, groups: [{ groupid: hg2 }])

  # update, refused: neither groups nor hosts would be left
  refused { maintenance.update({ maintenanceid: one, groups: [], hosts: [] }, true) }

  # the four upsert branches
  maintenance.create_or_update(name: Live.name(klass, 'one'), description: 'per upsert')
  Live.owns('maintenance', maintenance.create_or_update(base.merge(name: Live.name(klass, 'upserted'))))
  maintenance.get_or_create(name: Live.name(klass, 'one'))
  Live.owns('maintenance', maintenance.get_or_create(base.merge(name: Live.name(klass, 'gotten'))))

  # the two writing aliases, and the id type a delete echoes for an Integer
  added = Live.owns('maintenance', maintenance.add(base.merge(name: Live.name(klass, 'added'))))
  maintenance.destroy(added)
  Live.disown('maintenance', added)

  # delete with a String id, for the type the server echoes in that case
  disposable = Live.owns('maintenance', maintenance.create(base.merge(name: Live.name(klass, 'disposable'))))
  maintenance.delete(disposable.to_s)
  Live.disown('maintenance', disposable)

  # delete, refused: no maintenance carries that id
  refused { maintenance.delete(999999999) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
