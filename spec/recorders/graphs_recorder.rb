# Recorder for ZabbixApi::Graphs: runs the cases below against the server ZABBIX_URL names, through
# the gem itself, and writes spec/fixtures/graphs/crud.json.
#
# The scaffolding - one host group, two hosts, two numeric items on the first and one on the second
# - is built before Recorder.start!, so the fixture carries graph.* and graphitem.* exchanges only
# and the unit spec can index them by ordinal. The second host exists because a graph name is unique
# per host only: the twin on h2 is what makes get_id's refusal on more than one match, the collapse
# in all and the host scoping of get_ids_by_host observable at all. Trapper items need no interface,
# so neither host has one.
#
# The order below is the order the unit spec indexes the file in: three accepted creates and four
# refused ones, eleven reads, five updates with their dumps, the four upsert branches, the two
# writing aliases, a create deleted by its String id and a refused delete. Not recorded: all, whose
# output: 'extend' with no filter returns every graph on the server - the shared group drives it
# from recorded rows instead; a graph on a template and the copy a link inherits, which are server
# behaviour and put the very same request on the wire as a host graph, read back by the acceptance
# spec; enum values outside their documented ranges or reserved for pie and exploded graphs, which
# the server accepts and stores and which say nothing about the request the gem builds.
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
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/graphs_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

klass = 'graphs'
graphs = Live.session.graphs

# Hosts before groups: a group that is a host's only group cannot be deleted. Graphs are contents
# and are never pre-cleaned by name - they go away with their host.
Live.preclean(klass, 'host')
Live.preclean(klass, 'hostgroup')

group = Live.owns('hostgroup', Live.retrying('hostgroup.create') { Live.session.hostgroups.create(name: Live.name(klass, 'hg')) })
h1 = Live.owns('host', Live.retrying('host.create h1') { Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: group }]) })
h2 = Live.owns('host', Live.retrying('host.create h2') { Live.session.hosts.create(host: Live.name(klass, 'h2'), groups: [{ groupid: group }]) })
i1a = Live.retrying('item.create i1a') { Live.session.items.create(name: Live.name(klass, 'i1a'), key_: 'zbxapi.spec.graphs.v1', hostid: h1, type: 2, value_type: 3) }
i1b = Live.retrying('item.create i1b') { Live.session.items.create(name: Live.name(klass, 'i1b'), key_: 'zbxapi.spec.graphs.v2', hostid: h1, type: 2, value_type: 3) }
i2a = Live.retrying('item.create i2a') { Live.session.items.create(name: Live.name(klass, 'i2a'), key_: 'zbxapi.spec.graphs.v1', hostid: h2, type: 2, value_type: 3) }

Live::Recorder.start!
begin
  # create: name, width and height with one graph item
  base = graphs.create(name: Live.name(klass, 'base'), width: 900, height: 200, gitems: [{ itemid: i1a, color: '00AA00' }])

  # create: a normal graph with a fixed y axis, percentiles, and the legend, working time and
  # trigger line hidden, with two graph items
  full = graphs.create(name: Live.name(klass, 'full'), width: 1000, height: 300, graphtype: 0,
                       show_legend: 0, show_work_period: 0, show_triggers: 0,
                       yaxismin: 5, yaxismax: 50, ymin_type: 1, ymax_type: 1,
                       percent_left: 10, percent_right: 20,
                       gitems: [{ itemid: i1a, color: '00AA00', drawtype: 2, sortorder: 0, yaxisside: 1, calc_fnc: 4, type: 0 },
                                { itemid: i1b, color: '3333FF', drawtype: 5, sortorder: 1, yaxisside: 0, calc_fnc: 1, type: 0 }])

  # the twin: the same name on the other host, accepted
  twin = graphs.create(name: Live.name(klass, 'base'), width: 900, height: 200, gitems: [{ itemid: i2a, color: '00AA00' }])

  # create, refused: no gitems, which the graph.create reference requires and the graph object
  # reference does not list
  begin
    graphs.create(name: Live.name(klass, 'nogitems'), width: 900, height: 200)
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: a graph item's colour must be a hexadecimal code
  begin
    graphs.create(name: Live.name(klass, 'badcolor'), width: 900, height: 200, gitems: [{ itemid: i1a, color: 'not-a-colour' }])
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: that name is taken on that host
  begin
    graphs.create(name: Live.name(klass, 'base'), width: 900, height: 200, gitems: [{ itemid: i1b, color: '3333FF' }])
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: templateid, which the graph object reference marks read-only
  begin
    graphs.create(name: Live.name(klass, 'tplid'), width: 900, height: 200, templateid: 999999, gitems: [{ itemid: i1a, color: '00AA00' }])
  rescue ZabbixApi::ApiError
    nil
  end

  # the reads
  graphs.get_full_data(name: Live.name(klass, 'base'))                    # search:, and the name spans two hosts
  graphs.get_full_data(name: Live.prefix(klass))                          # a substring no graph carries as its whole name
  # two rows, so one_id! refuses once the exchange has been recorded
  begin
    graphs.get_id(name: Live.name(klass, 'base'))
  rescue ZabbixApi::ApiError
    nil
  end
  graphs.get_id(name: Live.name(klass, 'base'), hostid: h1)               # the whole hash filters, so this is exact
  graphs.get_id(name: Live.name(klass, 'absent'))                         # nothing
  graphs.dump_by_id(graphid: base)                                        # what the update skip compares against
  graphs.get_raw(graphids: [base], output: %w[graphid name])              # passed through untouched
  graphs.get_ids_by_host(host: Live.name(klass, 'h1'))                    # filter: {host:}
  graphs.get_ids_by_host(host: Live.name(klass, 'h1'), filter: 'base\z')  # the same request: the regexp never reaches the server
  graphs.get_items(full)                                                  # graphitem.get on a bare graph id
  begin
    graphs.get_items(graphids: full)                                      # refused: the Hash goes out as the graph id
  rescue ZabbixApi::ApiError
    nil
  end

  # update: issued, then skipped on the identical payload, then issued again under force
  graphs.update(graphid: base, height: 250)
  graphs.update(graphid: base, height: 250)
  graphs.update({ graphid: base, height: 250 }, true)

  # update: gitems, which no output: 'extend' dump carries, so the update is issued
  graphs.update(graphid: full, gitems: [{ itemid: i1a, color: 'FFAA00' }])

  # update, refused: templateid
  begin
    graphs.update(graphid: base, templateid: 999999)
  rescue ZabbixApi::ApiError
    nil
  end

  # create_or_update, update branch: the lookup takes name and hostid, the write drops hostid
  graphs.create_or_update(name: Live.name(klass, 'base'), hostid: h1, width: 950, gitems: [{ itemid: i1a, color: '00AA00' }])

  # create_or_update, create branch: that host carries no graph of the name
  graphs.create_or_update(name: Live.name(klass, 'cou'), hostid: h1, width: 900, height: 200, gitems: [{ itemid: i1a, color: '00AA00' }])

  # get_or_create: found on h1, and created when that host has none
  graphs.get_or_create(name: Live.name(klass, 'base'), hostid: h1)
  graphs.get_or_create(name: Live.name(klass, 'goc'), hostid: h1, width: 900, height: 200, gitems: [{ itemid: i1b, color: '3333FF' }])

  # the two writing aliases, and the id type graph.delete answers for an Integer
  added = graphs.add(name: Live.name(klass, 'added'), width: 900, height: 200, gitems: [{ itemid: i1a, color: '00AA00' }])
  graphs.destroy(added)

  # delete with a String id, for the type the server answers in that case
  disposable = graphs.create(name: Live.name(klass, 'disposable'), width: 900, height: 200, gitems: [{ itemid: i1a, color: '00AA00' }])
  graphs.delete(disposable.to_s)

  # delete, refused: no graph carries that id
  begin
    graphs.delete(999999999)
  rescue ZabbixApi::ApiError
    nil
  end

  puts "recorded against base #{base}, full #{full}, twin #{twin} on hosts #{h1} and #{h2}"
  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
