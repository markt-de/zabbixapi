# Recorder for ZabbixApi::ValueMaps: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/valuemaps/crud.json.
#
# The order below is the order spec/zabbixapi/classes/valuemaps_spec.rb indexes the file in: eight
# creates (the base map, five refusals, the twin carrying the same name on a second host, the
# template map), the nine reads, the five updates (skipped, issued, issued back, mappings, refused
# hostid), the four upsert branches, the two writing aliases, two deletes and the refusal of an id
# no value map carries.
#
# The host group, the two hosts, the template group and the template are scaffolding: they are built
# before Recorder.start! and therefore never reach the fixture, so what the unit spec replays is
# valuemap.* and nothing else. Value maps are contents and are never registered for teardown - they
# go with the host or template they belong to, which is; nor are they ever pre-cleaned by name.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Deliberately not recorded: `all`, whose output: extend answer is every value map on the server -
# the shared example group builds that table from two recorded rows instead; a forced update, which
# differs from the skipped one only in being issued and which the shared group proves offline; the
# delete of a value map an item references, whose exchange is indistinguishable from any other
# delete and whose point is the item's valuemapid afterwards, which only the acceptance spec can
# read back.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/valuemaps_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'securerandom'
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# A real UUIDv4 without its dashes, the only form the server accepts where it accepts one at all.
def uuid4
  SecureRandom.uuid.delete('-')
end

# A refusal is one of the cases being recorded, so the exchange is what matters and the exception is
# not. Only ApiError is swallowed: a transport failure must still abort the run.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

klass = 'valuemaps'
valuemaps = Live.session.valuemaps

# Hosts and templates before their groups: a group that is a host's only group cannot be deleted.
Live.preclean(klass, 'host')
Live.preclean(klass, 'template')
Live.preclean(klass, 'hostgroup')
Live.preclean(klass, 'templategroup')

# Scaffolding: a value map is content and needs a host or a template to belong to.
group = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'grp')))
tgroup = Live.owns('templategroup', Live.retrying('create template group') { Live.session.templategroups.create(name: Live.name(klass, 'tgrp')) })
h1 = Live.owns('host', Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: group }], status: 1))
h2 = Live.owns('host', Live.session.hosts.create(host: Live.name(klass, 'h2'), groups: [{ groupid: group }], status: 1))
tpl = Live.owns('template', Live.session.templates.create(host: Live.name(klass, 'tpl'), groups: [{ groupid: tgroup }]))

eq = [{ type: 0, value: '1', newvalue: 'Up' }]
two = [{ type: 0, value: '0', newvalue: 'Offline' }, { type: 0, value: '1', newvalue: 'Online' }]

Live::Recorder.start!
begin
  # create: hostid, name and one mapping are enough
  base = valuemaps.create(hostid: h1, name: Live.name(klass, 'base'), mappings: eq)

  # create, refused: a payload without mappings
  refused { valuemaps.create(hostid: h1, name: Live.name(klass, 'nomap')) }

  # create, refused: a type 0 mapping without newvalue
  refused { valuemaps.create(hostid: h1, name: Live.name(klass, 'nonewvalue'), mappings: [{ type: 0, value: '1' }]) }

  # create, refused: a type 5 mapping carrying a value
  refused { valuemaps.create(hostid: h1, name: Live.name(klass, 'ty5value'), mappings: [{ type: 5, value: 'x', newvalue: 'y' }]) }

  # create, refused: mapping type 6, which draws `value must be one of 0, 1, 2, 3, 4, 5.`
  refused { valuemaps.create(hostid: h1, name: Live.name(klass, 'badtype'), mappings: [{ type: 6, value: '1', newvalue: 'x' }]) }

  # create, refused: a uuid on a host's value map
  refused { valuemaps.create(hostid: h1, name: Live.name(klass, 'uuid'), mappings: eq, uuid: uuid4) }

  # create: the same name on the second host, which the API allows
  valuemaps.create(hostid: h2, name: Live.name(klass, 'base'), mappings: eq)

  # create: on a template
  tplmap = valuemaps.create(hostid: tpl, name: Live.name(klass, 'tplmap'), mappings: eq)

  # the reads
  valuemaps.get_full_data(name: Live.name(klass, 'base'))                  # spans both hosts
  valuemaps.get_id(name: Live.name(klass, 'base'), hostid: h1)             # scoped by hostid: the one map on h1
  # unscoped: two hosts carry the name, so one_id! refuses after the exchange is recorded
  begin
    valuemaps.get_id(name: Live.name(klass, 'base'))
  rescue ZabbixApi::ApiError
    nil
  end
  valuemaps.get_id(name: Live.name(klass, 'absent'))                       # nothing matches
  valuemaps.dump_by_id(valuemapid: base)
  valuemaps.get_raw(valuemapids: [base], selectMappings: 'extend')
  valuemaps.get_raw(valuemapids: [base], selectMappings: 'count')
  valuemaps.get_raw(hostids: [h1], output: %w[valuemapid name])            # undocumented and working
  valuemaps.dump_by_id(valuemapid: tplmap)                                 # the uuid a template map carries

  # update, skipped: the payload already matches the dump, so only the dump goes out
  valuemaps.update(valuemapid: base, name: Live.name(klass, 'base'))

  # update, issued - and issued back, so the upserts below find the map under its first name
  valuemaps.update(valuemapid: base, name: Live.name(klass, 'renamed'))
  valuemaps.update(valuemapid: base, name: Live.name(klass, 'base'))

  # update: mappings, which the output: extend dump lacks, so the call goes out
  valuemaps.update(valuemapid: base, mappings: two)

  # update, refused: the constant hostid
  refused { valuemaps.update(valuemapid: base, hostid: h1, name: Live.name(klass, 'moved')) }

  # create_or_update, update branch: the lookup, the dump, then the update without the hostid
  valuemaps.create_or_update(hostid: h1, name: Live.name(klass, 'base'), mappings: eq)

  # create_or_update, create branch: no map of that name on this host
  valuemaps.create_or_update(hostid: h1, name: Live.name(klass, 'cou'), mappings: eq)

  # get_or_create, both branches
  valuemaps.get_or_create(hostid: h1, name: Live.name(klass, 'base'), mappings: eq)
  valuemaps.get_or_create(hostid: h1, name: Live.name(klass, 'goc'), mappings: eq)

  # the two writing aliases
  added = valuemaps.add(hostid: h1, name: Live.name(klass, 'added'), mappings: eq)
  valuemaps.destroy(added)

  # delete, given an Integer id and given a String one, for the type the server answers each with
  valuemaps.delete(valuemaps.create(hostid: h1, name: Live.name(klass, 'gone1'), mappings: eq))
  valuemaps.delete(valuemaps.create(hostid: h1, name: Live.name(klass, 'gone2'), mappings: eq).to_s)

  # delete, refused: an id no value map carries
  refused { valuemaps.delete(999999999) }

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
  Live.preclean(klass, 'host')
  Live.preclean(klass, 'template')
  Live.preclean(klass, 'hostgroup')
  Live.preclean(klass, 'templategroup')
end
