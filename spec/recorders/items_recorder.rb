# Recorder for ZabbixApi::Items: runs the cases below against the server ZABBIX_URL names, through
# the gem itself, and writes spec/fixtures/items/crud.json.
#
# The scaffolding - one host group, a host with an agent interface and a second host without one -
# is built before Recorder.start!, so the fixture carries item.* exchanges only and the unit spec
# can index them by ordinal. The second host carries the twin, an item of base's name and key: it is
# what makes get_id's refusal on more than one match and get_full_data's span across hosts
# observable.
#
# The order below is the order the unit spec indexes the file in: three accepted creates (the
# default type, a trapper and a dependent item), four refused ones, the twin, the six reads, six
# updates with their dumps (one of them skipped), the four upsert branches, and the writing aliases
# with three deletes. Not recorded: all, whose output: 'extend' with no filter returns every item on
# the server - the shared group drives it from scripted rows instead; the delete cascade onto a
# dependent item and the inherited-copy refusals, which are server behaviour and are proven in the
# acceptance spec.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent. The scaffolding above is
# retried, being outside the file.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/items_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

klass = 'items'
items = Live.session.items

# Hosts before groups: a group that is a host's only group cannot be deleted. Items are contents
# and are never pre-cleaned by name - they go away with their host.
Live.preclean(klass, 'host')
Live.preclean(klass, 'hostgroup')

group = Live.owns('hostgroup', Live.retrying('hostgroup.create') { Live.session.hostgroups.create(name: Live.name(klass, 'hg')) })
h1 = Live.owns('host', Live.retrying('host.create h1') do
  Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: group }],
                            interfaces: [{ type: 1, main: 1, useip: 1, ip: '127.0.0.1', dns: '', port: '10050' }])
end)
h2 = Live.owns('host', Live.retrying('host.create h2') { Live.session.hosts.create(host: Live.name(klass, 'h2'), groups: [{ groupid: group }]) })

base_key = 'zbxapi.spec.items.base'

Live::Recorder.start!
begin
  # create: three parameters over the 18 defaults
  base = items.create(name: Live.name(klass, 'base'), key_: base_key, hostid: h1)

  # create: type 2 trapper, one of ZERO_DELAY_TYPES, so the class supplies delay 0 for its own '60'
  items.create(name: Live.name(klass, 'trap'), key_: 'zbxapi.spec.items.trap', hostid: h1, type: 2)

  # create: type 18 dependent as a String, sent with delay 0
  items.create(name: Live.name(klass, 'dep'), key_: 'zbxapi.spec.items.dep', hostid: h1, type: '18', master_itemid: base)

  # create, refused: an explicit delay goes out untouched, and the server answers
  # `Invalid parameter "/1/delay": value must be 0.`
  begin
    items.create(name: Live.name(klass, 'traptoo'), key_: 'zbxapi.spec.items.traptoo', hostid: h1, type: 2, delay: '1m')
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: the caller passes no key_
  begin
    items.create(name: Live.name(klass, 'nokey'), hostid: h1)
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: the key is taken on that host
  begin
    items.create(name: Live.name(klass, 'twinkey'), key_: base_key, hostid: h1)
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: type 9, web items, which the item.create reference says cannot be created via
  # the API
  begin
    items.create(name: Live.name(klass, 'web'), key_: 'zbxapi.spec.items.web', hostid: h1, type: 9, delay: '1m')
  rescue ZabbixApi::ApiError
    nil
  end

  # the twin: the same name and key on the other host, which the server accepts
  twin = items.create(name: Live.name(klass, 'base'), key_: base_key, hostid: h2, type: 2)

  # the reads
  items.get_full_data(name: Live.name(klass, 'base')) # filter on the name alone: spans hosts
  # two rows, so one_id! refuses once the exchange has been recorded
  begin
    items.get_id(name: Live.name(klass, 'base'))
  rescue ZabbixApi::ApiError
    nil
  end
  items.get_id(name: Live.name(klass, 'base'), hostid: h1)     # the whole hash filters, so this narrows to h1
  items.get_id(name: Live.name(klass, 'absent'))               # nothing
  items.dump_by_id(itemid: base)                               # what the update skip compares against
  items.get_raw(itemids: [base], output: %w[itemid name key_]) # passed through untouched

  # update: issued, then skipped on the identical payload, then issued again under force
  items.update(itemid: base, description: 'spec one')
  items.update(itemid: base, description: 'spec one')
  items.update({ itemid: base, description: 'spec one' }, true)

  # update: tags, which the extend dump lacks, so the update is issued
  items.update(itemid: base, tags: [{ tag: 'zbxapi-spec', value: klass }])

  # update, refused: hostid, which the item object reference marks constant
  begin
    items.update(itemid: base, hostid: h1, description: 'hostid must not reach the update')
  rescue ZabbixApi::ApiError
    nil
  end

  # update, refused: templateid, which the item object reference marks read-only
  begin
    items.update(itemid: base, templateid: 999999)
  rescue ZabbixApi::ApiError
    nil
  end

  # create_or_update, update branch: the lookup takes name and hostid, the update all but hostid
  items.create_or_update(name: Live.name(klass, 'base'), key_: base_key, hostid: h1, description: 'upserted')

  # create_or_update, create branch: nothing of that name on that host
  items.create_or_update(name: Live.name(klass, 'cou'), key_: 'zbxapi.spec.items.cou', hostid: h1)

  # get_or_create: found on h1, created when absent, and host-scoped to the twin on h2
  items.get_or_create(name: Live.name(klass, 'base'), hostid: h1)
  items.get_or_create(name: Live.name(klass, 'goc'), key_: 'zbxapi.spec.items.goc', hostid: h1, type: 2)
  items.get_or_create(name: Live.name(klass, 'base'), hostid: h2)

  # the two writing aliases, and the id type item.delete echoes for an Integer
  added = items.add(name: Live.name(klass, 'added'), key_: 'zbxapi.spec.items.added', hostid: h1)
  items.destroy(added)

  # delete with a String id, for the type the server echoes in that case
  disposable = items.create(name: Live.name(klass, 'disposable'), key_: 'zbxapi.spec.items.disposable', hostid: h1)
  items.delete(disposable.to_s)

  # delete, refused: no item carries that id
  begin
    items.delete(999999999)
  rescue ZabbixApi::ApiError
    nil
  end

  puts "recorded against base #{base}, twin #{twin} on hosts #{h1} and #{h2}"
  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
