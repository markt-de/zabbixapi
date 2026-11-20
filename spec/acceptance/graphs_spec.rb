# Contract: ZabbixApi::Graphs live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/graph,
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/graphitem
#   classes:  the minimal create stores the server's defaults | eleven non-default properties and
#             both graph items are stored | refusals: no gitems, a non-hex colour, a name taken on
#             the host, templateid, ymin_type 2 without its item | get_full_data matches a substring
#             where an exact filter matches nothing, and spans both hosts | get_id unscoped refuses
#             and scoped is exact | dump_by_id, one get_raw select representative, all |
#             get_ids_by_host keeps to its host and narrows client-side | get_items on a bare id,
#             and what a Hash does instead | update writes one field and a batch, leaves an
#             unchanged object alone, forces, replaces gitems, refuses templateid | hostid scopes a
#             lookup onto a template where templateid never could | the four upsert branches |
#             delete, the item cascade, an unknown id | the uuid of a template graph and of a host
#             graph | the inherited copy: templateid, refused rename and refused delete | aftercare
#   not here: the hooks and the wire shapes of create, the reads, update and the upserts, which
#             belong to the unit spec; enum values outside their documented ranges, on create and
#             update, reduced to one graph-level, one gitem-level and one update-side
#             representative, all three pending, and one value reserved for pie and exploded graphs,
#             pending too; the select options and get parameters of graph.get, one kept; the
#             deprecated selectGroups; sortfield, which the gem only passes through; the server's
#             graph count, which anything else using the server can change
require 'spec_helper'

RSpec.describe 'ZabbixApi::Graphs live', type: :acceptance do
  klass = 'graphs'
  tpl_key = 'zbxapi.spec.graphs.tplvalue'

  before(:all) do
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'template')
    Live.preclean(klass, 'hostgroup')
    Live.preclean(klass, 'templategroup')

    @group = Live.owns('hostgroup', Live.retrying('hostgroup.create') { Live.session.hostgroups.create(name: Live.name(klass, 'hg')) })
    @tplgroup = Live.owns('templategroup', Live.retrying('templategroup.create') { Live.session.templategroups.create(name: Live.name(klass, 'tgrp')) })
    @template = Live.owns('template', Live.retrying('template.create') { Live.session.templates.create(host: Live.name(klass, 'tpl'), groups: [{ groupid: @tplgroup }]) })

    # Trapper items need no interface, so neither host carries one.
    @h1 = Live.owns('host', Live.retrying('host.create h1') { Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: @group }]) })
    @h2 = Live.owns('host', Live.retrying('host.create h2') { Live.session.hosts.create(host: Live.name(klass, 'h2'), groups: [{ groupid: @group }]) })
    @i1a = Live.retrying('item.create i1a') { Live.session.items.create(name: Live.name(klass, 'i1a'), key_: 'zbxapi.spec.graphs.v1', hostid: @h1, type: 2, value_type: 3) }
    @i1b = Live.retrying('item.create i1b') { Live.session.items.create(name: Live.name(klass, 'i1b'), key_: 'zbxapi.spec.graphs.v2', hostid: @h1, type: 2, value_type: 3) }
    @i2a = Live.retrying('item.create i2a') { Live.session.items.create(name: Live.name(klass, 'i2a'), key_: 'zbxapi.spec.graphs.v1', hostid: @h2, type: 2, value_type: 3) }
    # The template's item key differs from the hosts': linking takes over a host item of the same
    # key, which then inherits from the template item.
    @itpl = Live.retrying('item.create itpl') { Live.session.items.create(name: Live.name(klass, 'itpl'), key_: tpl_key, hostid: @template, type: 2, value_type: 3) }

    @base = Live.retrying('graph.create base') { Live.session.graphs.create(name: Live.name(klass, 'base'), width: 900, height: 200, gitems: [{ itemid: @i1a, color: '00AA00' }]) }
    @twin = Live.retrying('graph.create twin') { Live.session.graphs.create(name: Live.name(klass, 'base'), width: 900, height: 200, gitems: [{ itemid: @i2a, color: '00AA00' }]) }
    @full = Live.retrying('graph.create full') do
      Live.session.graphs.create(name: Live.name(klass, 'full'), width: 1000, height: 300, graphtype: 0,
                                 show_legend: 0, show_work_period: 0, show_triggers: 0,
                                 yaxismin: 5, yaxismax: 50, ymin_type: 1, ymax_type: 1,
                                 percent_left: 10, percent_right: 20,
                                 gitems: [{ itemid: @i1a, color: '00AA00', drawtype: 2, sortorder: 0, yaxisside: 1, calc_fnc: 4, type: 0 },
                                          { itemid: @i1b, color: '3333FF', drawtype: 5, sortorder: 1, yaxisside: 0, calc_fnc: 1, type: 0 }])
    end
    @tplgraph = Live.retrying('graph.create tplgraph') { Live.session.graphs.create(name: Live.name(klass, 'tplgraph'), width: 800, height: 200, gitems: [{ itemid: @itpl, color: 'FF0000' }]) }
    Live.retrying('link template') { Live.raw('host.update', hostid: @h2, templates: [{ templateid: @template }]) }
  end

  after(:all) { Live.teardown }

  let(:graphs) { Live.session.graphs }
  # The copy the link minted on h2, looked up there by name: host.update answers only the host id.
  let(:inherited) { Live.retrying('inherited graph') { Live.one('graph', hostids: [@h2], filter: { name: Live.name(klass, 'tplgraph') }) } }

  describe 'create' do
    it 'stores the name and every documented server default' do
      stored = Live.one('graph', graphids: [@base])
      expect(stored['name']).to eq(Live.name(klass, 'base'))
      expect(stored.values_at('width', 'height')).to eq(%w[900 200])
      expect(stored.values_at('graphtype', 'show_3d', 'show_legend', 'show_work_period', 'show_triggers')).to eq(%w[0 0 1 1 1])
      expect(stored.values_at('yaxismin', 'yaxismax', 'percent_left', 'percent_right')).to eq(%w[0 100 0 0])
      expect(stored.values_at('ymin_type', 'ymax_type', 'ymin_itemid', 'ymax_itemid')).to eq(%w[0 0 0 0])
      expect(stored.values_at('flags', 'templateid', 'uuid')).to eq(['0', '0', ''])
    end

    it 'stores the eleven non-default properties sent besides the name, and both graph items, which only selectGraphItems returns' do
      stored = Live.one('graph', graphids: [@full])
      expect(stored.values_at('width', 'height', 'yaxismin', 'yaxismax')).to eq(%w[1000 300 5 50])
      expect(stored.values_at('show_legend', 'show_work_period', 'show_triggers')).to eq(%w[0 0 0])
      expect(stored.values_at('ymin_type', 'ymax_type', 'percent_left', 'percent_right')).to eq(%w[1 1 10 20])
      expect(stored).not_to have_key('gitems')

      items = Live.one('graph', graphids: [@full], selectGraphItems: 'extend')['gitems'].sort_by { |gitem| gitem['sortorder'].to_i }
      expect(items.map { |gitem| gitem['color'] }).to eq(%w[00AA00 3333FF])
      expect(items.first.values_at('drawtype', 'yaxisside', 'calc_fnc', 'type')).to eq(%w[2 1 4 0])
    end

    it 'refuses a create without gitems, which the graph.create reference requires and the graph object reference does not list' do
      expect { Live.retrying('create nogitems') { graphs.create(name: Live.name(klass, 'nogitems'), width: 900, height: 200) } }
        .to raise_error(ZabbixApi::ApiError, /Missing items for graph/)
    end

    it 'refuses a graph item colour that is not a hexadecimal code' do
      expect { Live.retrying('create badcolor') { graphs.create(name: Live.name(klass, 'badcolor'), width: 900, height: 200, gitems: [{ itemid: @i1a, color: 'not-a-colour' }]) } }
        .to raise_error(ZabbixApi::ApiError, /hexadecimal color code/)
    end

    it 'refuses a name another graph on that host already carries' do
      expect { Live.retrying('create duplicate') { graphs.create(name: Live.name(klass, 'base'), width: 900, height: 200, gitems: [{ itemid: @i1b, color: '3333FF' }]) } }
        .to raise_error(ZabbixApi::ApiError, /already exists on the host/)
    end

    it 'refuses templateid' do
      expect { Live.retrying('create tplid') { graphs.create(name: Live.name(klass, 'tplid'), width: 900, height: 200, templateid: 999999, gitems: [{ itemid: @i1a, color: '00AA00' }]) } }
        .to raise_error(ZabbixApi::ApiError, /Cannot set/)
    end

    it 'refuses ymin_type 2 without the item that is to supply the minimum' do
      expect { Live.retrying('create yminnoitem') { graphs.create(name: Live.name(klass, 'yminnoitem'), width: 900, height: 200, ymin_type: 2, gitems: [{ itemid: @i1a, color: '00AA00' }]) } }
        .to raise_error(ZabbixApi::ApiError, /ymin_itemid/)
    end

    it 'stores the item id when ymin_type 2 carries one' do
      graph = Live.retrying('create yminitem') do
        graphs.create(name: Live.name(klass, 'yminitem'), width: 900, height: 200, ymin_type: 2, ymin_itemid: @i1b, gitems: [{ itemid: @i1a, color: '00AA00' }])
      end
      stored = Live.one('graph', graphids: [graph])
      expect(stored['ymin_type']).to eq('2')
      expect(stored['ymin_itemid'].to_i).to eq(@i1b)
    end

    it 'refuses a create without width and height, which the graph object reference marks required' do
      pending 'the server accepts the omission and stores its undocumented defaults 900 and 200'
      expect { Live.retrying('create nosize') { graphs.create(name: Live.name(klass, 'nosize'), gitems: [{ itemid: @i1a, color: '00AA00' }]) } }
        .to raise_error(ZabbixApi::ApiError, /width/)
    end

    it 'refuses a graphtype outside the documented 0 to 3' do
      pending 'the server accepts 4 and stores it'
      expect { Live.retrying('create badtype') { graphs.create(name: Live.name(klass, 'badtype'), width: 900, height: 200, graphtype: 4, gitems: [{ itemid: @i1a, color: '00AA00' }]) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/graphtype})
    end

    it 'refuses a graph item drawtype outside the documented 0 to 5' do
      pending 'the server accepts 6 and stores it'
      expect { Live.retrying('create baddraw') { graphs.create(name: Live.name(klass, 'baddraw'), width: 900, height: 200, gitems: [{ itemid: @i1a, color: '00AA00', drawtype: 6 }]) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/gitems/1/drawtype})
    end

    it 'refuses calc_fnc 9 on a normal graph, which the reference reserves for pie and exploded graphs' do
      pending 'the server accepts calc_fnc 9 on graphtype 0 and stores it'
      expect { Live.retrying('create lastnormal') { graphs.create(name: Live.name(klass, 'lastnormal'), width: 900, height: 200, graphtype: 0, gitems: [{ itemid: @i1a, color: '00AA00', calc_fnc: 9 }]) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/gitems/1/calc_fnc})
    end
  end

  describe 'reads' do
    it 'get_full_data matches a substring, where an exact filter on the same string matches nothing' do
      partial = Live.name(klass, 'ba')
      found = Live.retrying('get_full_data partial') { graphs.get_full_data(name: partial) }
      expect(found.map { |graph| graph['graphid'].to_i }).to include(@base, @twin)
      expect(Live.count('graph', filter: { name: partial })).to eq(0)
    end

    it 'get_full_data on the whole name spans both hosts' do
      found = Live.retrying('get_full_data') { graphs.get_full_data(name: Live.name(klass, 'base')) }
      expect(found.map { |graph| graph['graphid'].to_i }).to match_array([@base, @twin])
      expect(found.first).to include('uuid', 'flags', 'templateid')
    end

    it 'get_id without a hostid refuses, reporting two matches' do
      expect { Live.retrying('get_id') { graphs.get_id(name: Live.name(klass, 'base')) } }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 graph objects, not one \(graphid /)
    end

    it "get_id with a hostid returns that host's graph, and the other host's for the other id" do
      expect(Live.retrying('get_id h1') { graphs.get_id(name: Live.name(klass, 'base'), hostid: @h1) }).to eq(@base)
      expect(Live.retrying('get_id h2') { graphs.get_id(name: Live.name(klass, 'base'), hostid: @h2) }).to eq(@twin)
    end

    it 'get_id returns nil for a name no graph carries' do
      expect(Live.retrying('get_id absent') { graphs.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'dump_by_id returns the one graph of that id' do
      expect(Live.retrying('dump_by_id') { graphs.dump_by_id(graphid: @base) }.map { |graph| graph['graphid'].to_i }).to eq([@base])
    end

    it 'get_raw passes a documented parameter through: selectGraphItems, which returns gitems and not graphitems' do
      row = Live.retrying('get_raw') { graphs.get_raw(graphids: [@full], output: %w[graphid], selectGraphItems: 'extend') }.first
      expect(row.keys).to match_array(%w[graphid gitems])
      expect(row['gitems'].size).to eq(2)
    end

    it 'all maps the name to an Integer id and collapses the two graphs of that name into one entry' do
      table = Live.retrying('all') { graphs.all }
      expect(table[Live.name(klass, 'base')]).to be_a(Integer)
      expect([@base, @twin]).to include(table[Live.name(klass, 'base')])
      expect(Live.count('graph', filter: { name: Live.name(klass, 'base') })).to eq(2)
    end

    it "get_ids_by_host returns that host's graphs and not the twin on the other host" do
      ids = Live.retrying('get_ids_by_host') { graphs.get_ids_by_host(host: Live.name(klass, 'h1')) }
      expect(ids).to include(@base, @full)
      expect(ids).not_to include(@twin)
    end

    it 'get_ids_by_host narrows its answer by a Ruby regexp over the names, to an empty Array where none matches' do
      expect(Live.retrying('get_ids_by_host regexp') { graphs.get_ids_by_host(host: Live.name(klass, 'h1'), filter: 'base\z') }).to eq([@base])
      expect(Live.retrying('get_ids_by_host nothing') { graphs.get_ids_by_host(host: Live.name(klass, 'h1'), filter: 'no-such-graph') }).to eq([])
    end

    it 'get_items takes a bare graph id and returns the graph items of that graph' do
      items = Live.retrying('get_items') { graphs.get_items(@full) }
      expect(items.map { |gitem| gitem['graphid'].to_i }.uniq).to eq([@full])
      expect(items.first.keys).to include('gitemid', 'itemid', 'color')
    end

    it 'get_items given a Hash is refused with a database error' do
      expect { Live.retrying('get_items hash') { graphs.get_items(graphids: @full) } }.to raise_error(ZabbixApi::ApiError, /Database error occurred/)
    end
  end

  describe 'update' do
    it 'writes one field and it reads back' do
      expect(Live.retrying('update one') { graphs.update(graphid: @base, height: 250) }).to eq(@base)
      expect(Live.one('graph', graphids: [@base])['height']).to eq('250')
    end

    it 'writes several properties in one call and every one reads back' do
      expect(Live.retrying('update batch') { graphs.update(graphid: @base, width: 950, height: 260, show_legend: 0, graphtype: 1) }).to eq(@base)
      stored = Live.one('graph', graphids: [@base])
      expect(stored.values_at('width', 'height', 'show_legend', 'graphtype')).to eq(%w[950 260 0 1])
    end

    it 'returns the id and leaves the object exactly as it was when nothing differs' do
      before_state = Live.one('graph', graphids: [@base])
      expect(Live.retrying('update unchanged') { graphs.update(graphid: @base, width: 950, height: 260, show_legend: 0, graphtype: 1) }).to eq(@base)
      expect(Live.one('graph', graphids: [@base])).to eq(before_state)
    end

    it 'returns the id for a forced update, and the width and height read back as sent' do
      expect(Live.retrying('update forced') { graphs.update({ graphid: @base, width: 950, height: 260, show_legend: 0, graphtype: 1 }, true) }).to eq(@base)
      expect(Live.one('graph', graphids: [@base]).values_at('width', 'height')).to eq(%w[950 260])
    end

    it 'replaces the graph items rather than merging them' do
      expect(Live.retrying('update gitems') { graphs.update(graphid: @full, gitems: [{ itemid: @i1a, color: 'FFAA00' }]) }).to eq(@full)
      items = Live.one('graph', graphids: [@full], selectGraphItems: 'extend')['gitems']
      expect(items.size).to eq(1)
      expect(items.first['color']).to eq('FFAA00')
    end

    it 'is refused for templateid' do
      expect { Live.retrying('update templateid') { graphs.update(graphid: @base, templateid: 999999) } }.to raise_error(ZabbixApi::ApiError, /Cannot update/)
    end

    it 'refuses a graphtype outside the documented 0 to 3' do
      pending 'graph.update accepts 4 and stores it, exactly as graph.create does'
      disposable = Live.retrying('create updbad') { graphs.create(name: Live.name(klass, 'updbad'), width: 900, height: 200, gitems: [{ itemid: @i1a, color: '00AA00' }]) }
      expect { Live.retrying('update badtype') { graphs.update(graphid: disposable, graphtype: 4) } }.to raise_error(ZabbixApi::ApiError, %r{/1/graphtype})
    end
  end

  describe 'upserts and what hostid scopes' do
    it 'stores templateid 0 for a graph created on a template, so scoping by the template id matches nothing' do
      expect(Live.one('graph', graphids: [@tplgraph])['templateid']).to eq('0')
      expect(Live.retrying('get_id by templateid') { graphs.get_id(name: Live.name(klass, 'tplgraph'), templateid: @template) }).to be_nil
    end

    it 'get_id scoped by hostid resolves the graph on the template' do
      expect(Live.retrying('get_id by hostid') { graphs.get_id(name: Live.name(klass, 'tplgraph'), hostid: @template) }).to eq(@tplgraph)
    end

    it 'get_or_create scoped by hostid returns the graph on the template and creates no second one' do
      expect(Live.retrying('get_or_create template') { graphs.get_or_create(name: Live.name(klass, 'tplgraph'), width: 800, height: 200, hostid: @template, gitems: [{ itemid: @itpl, color: 'FF0000' }]) })
        .to eq(@tplgraph)
      expect(Live.count('graph', templated: true, filter: { name: Live.name(klass, 'tplgraph') })).to eq(1)
    end

    it 'create_or_update scoped by hostid updates the graph on the template despite a stray templateid' do
      expect(Live.retrying('create_or_update template') { graphs.create_or_update(name: Live.name(klass, 'tplgraph'), width: 400, hostid: @template, templateid: 999999, gitems: [{ itemid: @itpl, color: 'FF0000' }]) })
        .to eq(@tplgraph)
      expect(Live.one('graph', graphids: [@tplgraph])['width']).to eq('400')
    end

    it 'create_or_update updates the host graph of that name without duplicating it' do
      expect(Live.retrying('upsert update') { graphs.create_or_update(name: Live.name(klass, 'base'), hostid: @h1, width: 960, gitems: [{ itemid: @i1a, color: '00AA00' }]) }).to eq(@base)
      expect(Live.one('graph', graphids: [@base])['width']).to eq('960')
      expect(Live.count('graph', hostids: [@h1], filter: { name: Live.name(klass, 'base') })).to eq(1)
    end

    it 'create_or_update creates when that host carries no graph of the name' do
      created = Live.retrying('upsert create') { graphs.create_or_update(name: Live.name(klass, 'cou'), hostid: @h1, width: 900, height: 200, gitems: [{ itemid: @i1a, color: '00AA00' }]) }
      expect(Live.one('graph', graphids: [created])['name']).to eq(Live.name(klass, 'cou'))
    end

    it 'get_or_create creates when that host carries no graph of the name' do
      created = Live.retrying('get_or_create create') { graphs.get_or_create(name: Live.name(klass, 'goc'), hostid: @h1, width: 900, height: 200, gitems: [{ itemid: @i1b, color: '3333FF' }]) }
      expect(Live.one('graph', graphids: [created])['name']).to eq(Live.name(klass, 'goc'))
    end
  end

  describe 'the template graph and its inherited copy' do
    it 'the template graph carries a server-generated uuid and the host graph none' do
      expect(Live.one('graph', graphids: [@tplgraph])['uuid']).to match(/\A[0-9a-f]{32}\z/)
      expect(Live.one('graph', graphids: [@base])['uuid']).to eq('')
    end

    it 'the copy points its templateid at the parent template graph, not at the template' do
      expect(inherited['templateid'].to_i).to eq(@tplgraph)
      expect(Live.retrying('get_id by parent') { graphs.get_id(name: Live.name(klass, 'tplgraph'), templateid: @tplgraph) }).to eq(inherited['graphid'].to_i)
    end

    it 'refuses a rename on the copy' do
      expect { Live.retrying('update rename inherited') { graphs.update(graphid: inherited['graphid'].to_i, name: Live.name(klass, 'renamed')) } }
        .to raise_error(ZabbixApi::ApiError, /templated graph/)
    end

    it 'refuses to delete the copy directly' do
      expect { Live.retrying('delete inherited') { graphs.delete(inherited['graphid'].to_i) } }.to raise_error(ZabbixApi::ApiError, /templated graph/)
    end
  end

  describe 'delete' do
    it 'removes the graph and returns its id' do
      disposable = Live.retrying('create disposable') { graphs.create(name: Live.name(klass, 'disposable'), width: 900, height: 200, gitems: [{ itemid: @i1a, color: '00AA00' }]) }
      expect(Live.retrying('delete') { graphs.delete(disposable) }).to eq(disposable)
      expect(Live.get('graph', graphids: [disposable])).to eq([])
    end

    it 'goes away with the item it draws, which the item.delete reference does not mention' do
      item = Live.retrying('create cascade item') { Live.session.items.create(name: Live.name(klass, 'icas'), key_: 'zbxapi.spec.graphs.cascade', hostid: @h1, type: 2, value_type: 3) }
      graph = Live.retrying('create cascade graph') { graphs.create(name: Live.name(klass, 'cascade'), width: 900, height: 200, gitems: [{ itemid: item, color: '00AA00' }]) }
      expect(Live.retrying('delete cascade item') { Live.session.items.delete(item) }).to eq(item)
      expect(Live.get('graph', graphids: [graph])).to eq([])
    end

    it 'is refused for an id no graph carries' do
      expect { Live.retrying('delete unknown') { graphs.delete(999999999) } }.to raise_error(ZabbixApi::ApiError, /does not exist/)
    end
  end

  describe 'aftercare' do
    it 'leaves no graph, host, template, host group or template group under its prefix once torn down, and the standing hosts and proxy still present' do
      Live.teardown
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('template', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('templategroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('graph', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
