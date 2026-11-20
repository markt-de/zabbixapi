# Recorder for ZabbixApi::Problems: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/problems/reads.json.
#
# This class creates nothing. problem.get is the whole documented surface of the problem API, the
# five CRUD methods and the two aliases raise before a request exists, and the standing problem is
# this class's read fixture. It is resolved through its host's name, read and never written;
# EventGuard.protect! records it, and every other problem an unfiltered problem.get returns, before
# the first recorded call, so EventGuard.ack! would refuse them.
#
# The order below is the order the unit spec indexes the file in: all, the name filter, the get
# alias, a name nothing carries, twenty-two settable parameters, the nine others, the overridable
# output, countOutput both ways, get_id twice, dump_by_id, one get_raw passthrough and four
# refusals. Not recorded: the seven write entry points, which raise locally and send nothing at all
# - there is no exchange for a request that never happens, and the unit spec proves the silence
# through FakeClient#calls instead.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts;
# nothing was created, so nothing is left behind.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/problems_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/event_guard'
require_relative '../support/live/recorder'

klass = 'problems'
problems = Live.session.problems

# Everything below the recorder's start! is a read of this fixture, so it is measured first and
# never assumed: the host by name, the problem on it, its group, and the token's owner.
Live::EventGuard.protect!
host = Live.one('host', filter: { host: Live::STANDING_PROBLEM_HOST }, output: %w[hostid host])
raise "the stock host #{Live::STANDING_PROBLEM_HOST}, which carries the standing problem, is not on this server" if host.nil?

hostid = host['hostid'].to_i
standing = Live.one('problem', hostids: [hostid], selectTags: 'extend')
raise "no problem stands on #{Live::STANDING_PROBLEM_HOST}; this class has no read fixture without one" if standing.nil?

eventid = standing['eventid'].to_i
name = standing['name']
groups = Live.one('host', hostids: [hostid], selectHostGroups: %w[groupid name])['hostgroups']
groupid = groups.first['groupid'].to_i
owner = Live.raw('user.checkAuthentication', token: Live.token)['userid'].to_i
absent = Live.name(klass, 'no-such-problem')

# Twenty-two of the 32 parameters Problems#get_full_data forwards, every one of them supplied, those
# naming the problem being read, its trigger, host, group, severity or clock with its own values.
# `name` goes into the filter instead, and the nine below complete the set beside `output`.
settable = {
  eventids: [eventid], groupids: [groupid], hostids: [hostid], objectids: [standing['objectid'].to_i],
  source: 0, object: 0, acknowledged: false, action: 2, action_userids: [owner],
  suppressed: false, symptom: false, severities: [standing['severity'].to_i], evaltype: 2, tags: [],
  recent: true, eventid_from: eventid.to_s, eventid_till: eventid.to_s,
  time_from: standing['clock'].to_i, time_till: standing['clock'].to_i,
  sortfield: %w[eventid], sortorder: 'ASC', countOutput: false
}

# The nine that complete the 32 beside output, every one of them supplied.
forwarded = {
  filter: { severity: 3 }, search: { name: name }, searchByAny: true,
  searchWildcardsEnabled: true, startSearch: true, excludeSearch: true,
  editable: true, limit: 1, preservekeys: true
}

Live::Recorder.start!
begin
  problems.all                                   # the six defaults and three selects, no filter
  problems.get_full_data(name: name)             # the identify value as a name filter
  problems.get(name: name)                       # the alias, the same request
  problems.get_full_data(name: absent)           # a name no problem carries
  problems.get_full_data(settable)               # twenty-two of the settable parameters
  problems.get_full_data(forwarded)              # all nine reach the wire
  problems.get_full_data(output: %w[eventid])    # output narrowed, the three selects beside it
  problems.get_full_data(countOutput: true)      # sortfield dropped, the count as a String
  problems.get_full_data(countOutput: false)     # an explicit false survives compact_params
  problems.get_id(name: name)                    # filter name, output eventid and name
  problems.get_id(name: absent)                  # nothing matches
  problems.dump_by_id(eventid: eventid)          # filter eventid, output extend
  problems.get_raw(eventids: [eventid], output: %w[eventid name], selectAcknowledges: 'count')

  # The refusals, each recorded with the error the server sent.
  [
    { sortfield: %w[clock] },                      # sortfield takes eventid alone, as the problem.get reference documents
    { filter: { suppressed: 0 } },                 # the filter refuses suppressed
    { countOutput: true, sortfield: %w[eventid] }, # both documented, together refused
    { source: 9 }                                  # an undocumented event source
  ].each do |params|
    problems.get_raw(params)
  rescue ZabbixApi::ApiError
    nil
  end

  Live::Recorder.write(klass, 'reads')
ensure
  Live.teardown
end
