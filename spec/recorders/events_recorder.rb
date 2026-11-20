# Recorder for ZabbixApi::Events: runs the cases below against the server ZABBIX_URL names, through
# the gem itself, and writes spec/fixtures/events/reads.json and
# spec/fixtures/events/acknowledge.json.
#
# There is no crud scenario, because events are created by the server: the five write methods raise
# locally and send nothing, so none of them is called here - a refusal that never reaches the client
# has no exchange to record. What the two fixtures hold is the read surface and the one write the
# event API does offer, both against events this run manufactured and owns.
#
# The fixture host, its trapper item and its two triggers are built, fired, recovered and fired
# again *before* Live::Recorder.start!, so that no host.create, item.create, trigger.create,
# history.push or problem.get lands in the file and the indices below are exactly the event.get
# exchanges the unit spec addresses. Firing twice around a recovery is what gives the closeable
# trigger three events under one name - problem, recovery, problem - the collapse an identify of
# `name` cannot survive.
#
# The order the unit spec indexes event.get in:
#   0  dump_by_id(eventid:)                      filter eventid, output extend, one open problem
#   1  get_full_data(name:)                      filter name, output extend, the rows sharing it
#   2  get_id(name:)                             filter name, output [eventid, name]
#   3  get_id(name: <no event carries it>)       the same shape, empty result
#   4  get_raw(eventids:, output:)               a field list passed through untouched
#   5  get_raw(..., selectAcknowledges, selectHosts, selectTags)   one select* representative
#   6  get_raw(objectids:, countOutput: true)    the count, which comes back as a String
#   7  get_raw(sortfield: 'name')                refused: the error exchange
#
# The acknowledge scenario in the same way, each ack! preceded by the guard's own ownership read,
# so the event.acknowledge exchanges are indexed 0 to 3 and the event.get ones interleave:
#   0  action 2 on the closeable event           accepted, one id back
#   1  action 4 and a message on both events     accepted, both ids back - the bulk shape
#   2  action 2 on that same event again         accepted, one id back, though already acknowledged
#   3  action 1 on the locked event              refused: its trigger forbids manual closing
#
# Live.retrying wraps nothing but single-request calls, because a retry re-issues every request
# its block made: a gem call that sends two requests and meets a transient on the second records
# the first twice. Inside the recording that is the guard's ownership read before each
# acknowledge, Live.get underneath, so a transient there is retried and recorded once. On any
# other recorded call the recorder's hook raises a transient as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, it passes the refusal rescues: the run aborts, and
# the ensure recovers and tears down. Everything before Live::Recorder.start! is retried, through
# the helpers' own Live.retrying, and the pre-clean makes a re-run idempotent.
#
# Safety: every problem an unfiltered problem.get returns is protected before the fixture exists, no
# action of any event source may be enabled, Live::EventGuard is the only route to history.push and
# to event.acknowledge, every acknowledged id is one this run manufactured - the guard refuses a
# protected id before it reads anything - and the ensure recovers our problems before the teardown
# removes the host.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/events_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the files to /tmp instead and prints their paths.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/event_guard'
require_relative '../support/live/recorder'

klass = 'events'
events = Live.session.events

Live.preclean(klass, 'host')
Live.preclean(klass, 'hostgroup')

armed = Live::EventGuard.armed
raise "#{armed.length} action(s) are enabled - a manufactured problem could notify or execute" unless armed.empty?

Live::EventGuard.protect!
fixture = Live::EventGuard.build(klass)
begin
  # The first push is accepted only once the configuration cache holds the trapper item, which the
  # manual's Zabbix trapper page allows up to 60 s, so the default bound of 60 s is not enough.
  Live::EventGuard.fire!(5, problems: 2, max: 150)
  Live::EventGuard.recover!
  opened = Live::EventGuard.fire!(5, problems: 2)
  closeable = opened.find { |row| row['objectid'].to_i == fixture[:closeable] }['eventid'].to_i
  locked = opened.find { |row| row['objectid'].to_i == fixture[:locked] }['eventid'].to_i
  name = Live.one('event', eventids: [closeable], output: ['name'])['name']

  Live::Recorder.start!

  # the reads
  events.dump_by_id(eventid: closeable)
  events.get_full_data(name: name)
  # get_id, refused client-side: several events carry the name, so the exchange is recorded and
  # one_id! then refuses. Wrapped so the calls below still run.
  begin
    events.get_id(name: name)
  rescue ZabbixApi::ApiError
    nil
  end
  events.get_id(name: Live.name(klass, 'no-such-event'))
  events.get_raw(eventids: [closeable, locked], output: %w[eventid name value severity])
  events.get_raw(eventids: [closeable], output: ['eventid'], selectAcknowledges: 'extend', selectHosts: %w[hostid host], selectTags: 'extend')
  events.get_raw(objectids: Live::EventGuard.own[:triggers], countOutput: true)

  # get_raw, refused: name is not among the values sortfield takes
  begin
    events.get_raw(sortfield: 'name', output: ['eventid'])
  rescue ZabbixApi::ApiError
    nil
  end

  Live::Recorder.write(klass, 'reads')

  # The write surface: event.acknowledge, the one write the event API offers, always through the
  # guard. action 2 is the acknowledge bit - the reference calls it 6, which is 2+4 and is refused
  # without a message.
  Live::Recorder.start!

  Live::EventGuard.ack!({ eventids: closeable, action: 2 }, 'acknowledge')
  Live::EventGuard.ack!({ eventids: [closeable, locked], action: 4, message: 'zbxapi-spec note' }, 'message both')

  # accepted, although the event already carries that action
  Live::EventGuard.ack!({ eventids: closeable, action: 2 }, 'acknowledge again')

  # refused: trg-locked was created with manual_close 0
  begin
    Live::EventGuard.ack!({ eventids: locked, action: 1 }, 'close the locked one')
  rescue ZabbixApi::ApiError
    nil
  end

  Live::Recorder.write(klass, 'acknowledge')
ensure
  begin
    Live::EventGuard.recover!
  rescue StandardError => e
    warn "  [recover] our problems were not recovered before teardown: #{e.class}"
  end
  Live.teardown
end
