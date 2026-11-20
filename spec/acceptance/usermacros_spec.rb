# Contract: ZabbixApi::Usermacros live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/usermacro
#   classes:  create stores the macro and the server's defaults | the same name lives on two hosts
#             and refuses a second time on one | refusals: missing hostid, macro syntax, automatic,
#             the type enum | secret and vault types, and the value a secret macro never returns
#             again | the global surface: create, its refusals, and a name held on a host and
#             globally at once | get_id scoped per host against get_id_global | get_full_data spans
#             hosts until a hostid narrows it | dump_by_id, all, one get_raw representative |
#             update writes and is refused for the constant hostid and the missing id | the same
#             for update_global | the four host upsert branches and the four global ones | delete
#             and delete_global, accepted and refused | a template macro is a host macro on the
#             template and linking does not copy it | aftercare
#   not here: that update sends no dump first and that the upserts strip the scope from the payload
#             - both are traffic, not state, and are asserted offline; the documented get parameters
#             beyond one select and one sortfield; `all` as a count, which spans every host macro on
#             the server, so only membership is asserted; bulk arrays, which Usermacros#create,
#             #delete, #create_global and #delete_global send as one call through the private
#             request, not through Basic, a path no spec runs on an Array
require 'spec_helper'

RSpec.describe 'ZabbixApi::Usermacros live', type: :acceptance do
  klass = 'usermacros'
  base = Live.macro(klass, 'base')
  globally = Live.macro(klass, 'gbase')
  absent = Live.macro(klass, 'absent')

  before(:all) do
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'template')
    Live.preclean(klass, 'hostgroup')
    Live.preclean(klass, 'templategroup')
    Live.preclean_macros(klass)

    @group = Live.owns('hostgroup', Live.retrying('group') { Live.session.hostgroups.create(name: Live.name(klass, 'grp')) })
    @tgroup = Live.owns('templategroup', Live.retrying('template group') { Live.session.templategroups.create(name: Live.name(klass, 'tgrp')) })
    @template = Live.owns('template', Live.retrying('template') { Live.session.templates.create(host: Live.name(klass, 'tpl'), groups: [{ groupid: @tgroup }]) })
    @h1 = Live.owns('host', Live.retrying('h1') { Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: @group }]) })
    @h2 = Live.owns('host', Live.retrying('h2') { Live.session.hosts.create(host: Live.name(klass, 'h2'), groups: [{ groupid: @group }]) })

    # Host macros are contents: they are never registered and never pre-cleaned by name, they go
    # with their host. Global macros are server-wide and each one is registered at once.
    @base = Live.retrying('base macro') { Live.session.usermacros.create(hostid: @h1, macro: base, value: 'v1') }
    @other = Live.retrying('other macro') { Live.session.usermacros.create(hostid: @h2, macro: base, value: 'v2') }
    @global = Live.owns('globalmacro', Live.retrying('global macro') { Live.session.usermacros.create_global(macro: globally, value: 'g1') }) { |id| Live.raw('usermacro.deleteglobal', [id]) }
  end

  after(:all) { Live.teardown }

  let(:usermacros) { Live.session.usermacros }

  describe 'create' do
    it 'stores the macro on its host and leaves type, description and automatic at the server default' do
      stored = Live.one('usermacro', hostmacroids: [@base])
      expect(stored['macro']).to eq(base)
      expect(stored['value']).to eq('v1')
      expect(stored['hostid'].to_i).to eq(@h1)
      expect([stored['type'], stored['description'], stored['automatic']]).to eq(['0', '', '0'])
    end

    it 'accepts the same macro name on a second host' do
      stored = Live.one('usermacro', hostmacroids: [@other])
      expect([stored['macro'], stored['value'], stored['hostid'].to_i]).to eq([base, 'v2', @h2])
    end

    it 'refuses the same macro twice on one host' do
      expect { Live.retrying('create duplicate') { usermacros.create(hostid: @h1, macro: base, value: 'again') } }.to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses a create without a hostid' do
      expect { Live.retrying('create nohost') { usermacros.create(macro: Live.macro(klass, 'nohost'), value: 'v') } }.to raise_error(ZabbixApi::ApiError, %r{Invalid parameter .*/1.*: the parameter .*hostid.* is missing})
    end

    it 'refuses a macro name outside the {$NAME} form' do
      expect { Live.retrying('create badmacro') { usermacros.create(hostid: @h1, macro: 'not_a_macro', value: 'v') } }.to raise_error(ZabbixApi::ApiError, %r{Invalid parameter .*/1/macro})
    end

    # The usermacro object reference states "User is not allowed to create automatic macro." but
    # leaves the property unmarked in its table.
    it 'refuses automatic as an unexpected parameter' do
      expect { Live.retrying('create automatic') { usermacros.create(hostid: @h1, macro: Live.macro(klass, 'auto'), value: 'v', automatic: 1) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*automatic/)
    end

    it 'refuses a type outside the enum at either bound' do
      [3, -1].each do |type|
        expect { Live.retrying('create badtype') { usermacros.create(hostid: @h1, macro: Live.macro(klass, 'badtype'), value: 'v', type: type) } }.to raise_error(ZabbixApi::ApiError, /value must be one of 0, 1, 2/)
      end
    end
  end

  describe 'the macro types' do
    it 'reads a secret macro back with type 1 and no value' do
      created = Live.retrying('secret') { usermacros.create(hostid: @h1, macro: Live.macro(klass, 'secret'), value: 'zbxapi-spec-usermacros-secret', type: 1) }
      stored = Live.one('usermacro', hostmacroids: [created])
      expect(stored['type']).to eq('1')
      expect(stored).not_to have_key('value')
    end

    it 'hides the value of a text macro once its type is flipped to secret' do
      created = Live.retrying('flipped') { usermacros.create(hostid: @h1, macro: Live.macro(klass, 'flipped'), value: 'readable') }
      expect(Live.one('usermacro', hostmacroids: [created])['value']).to eq('readable')

      Live.retrying('flip') { usermacros.update(hostmacroid: created, type: 1) }
      expect(Live.one('usermacro', hostmacroids: [created])).not_to have_key('value')
    end

    it 'stores a vault macro whose value is path:key and refuses one whose value is not' do
      created = Live.retrying('vault') { usermacros.create(hostid: @h1, macro: Live.macro(klass, 'vault'), value: 'secret/zbxapi-spec-usermacros:key', type: 2) }
      expect(Live.one('usermacro', hostmacroids: [created])['type']).to eq('2')

      expect { Live.retrying('create badvault') { usermacros.create(hostid: @h1, macro: Live.macro(klass, 'badvault'), value: 'novaultformat', type: 2) } }.to raise_error(ZabbixApi::ApiError, /Invalid parameter/)
    end
  end

  describe 'the global surface' do
    it 'creates a global macro, which carries no hostid property at all' do
      stored = Live.raw('usermacro.get', globalmacro: true, globalmacroids: [@global], output: 'extend').first
      expect([stored['macro'], stored['value'], stored['type']]).to eq([globally, 'g1', '0'])
      expect(stored).not_to have_key('hostid')
    end

    it 'carries a name a host macro holds too, with a value of its own' do
      same = Live.owns('globalmacro', Live.retrying('same name') { usermacros.create_global(macro: base, value: 'global-one') }) { |id| Live.raw('usermacro.deleteglobal', [id]) }
      expect(Live.raw('usermacro.get', globalmacro: true, globalmacroids: [same], output: 'extend').first['value']).to eq('global-one')
      expect(Live.one('usermacro', hostmacroids: [@base])['value']).to eq('v1')
    end

    it 'refuses a global macro name that is already taken' do
      expect { Live.retrying('create_global duplicate') { usermacros.create_global(macro: globally, value: 'again') } }.to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses a hostid' do
      expect { Live.retrying('create_global hostid') { usermacros.create_global(macro: Live.macro(klass, 'ghost'), value: 'g', hostid: @h1) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*hostid/)
    end

    it 'refuses a global macro without a value' do
      expect { Live.retrying('create_global novalue') { usermacros.create_global(macro: Live.macro(klass, 'gnoval')) } }.to raise_error(ZabbixApi::ApiError, /the parameter .*value.* is missing/)
    end
  end

  describe 'reads' do
    it 'get_id returns the macro of the host it was scoped to, and the other host has its own' do
      expect(Live.retrying('get_id h1') { usermacros.get_id(macro: base, hostid: @h1) }).to eq(@base)
      expect(Live.retrying('get_id h2') { usermacros.get_id(macro: base, hostid: @h2) }).to eq(@other)
    end

    it 'get_id_global returns the global macro of that name' do
      expect(Live.retrying('get_id_global') { usermacros.get_id_global(macro: globally) }).to eq(@global)
      expect(@global).not_to eq(@base)
    end

    it 'get_id_global ignores a hostid' do
      expect(Live.retrying('stray hostid') { usermacros.get_id_global(macro: globally, hostid: @h1) }).to eq(@global)
    end

    it 'both lookups return nil for a macro nothing carries' do
      expect(Live.retrying('absent host') { usermacros.get_id(macro: absent, hostid: @h1) }).to be_nil
      expect(Live.retrying('absent global') { usermacros.get_id_global(macro: absent) }).to be_nil
    end

    it 'get_full_data spans both hosts and narrows to one when the payload carries a hostid' do
      both = Live.retrying('get_full_data') { usermacros.get_full_data(macro: base) }
      expect(both.map { |found| found['hostmacroid'].to_i }).to match_array([@base, @other])

      scoped = Live.retrying('get_full_data scoped') { usermacros.get_full_data(macro: base, hostid: @h1) }
      expect(scoped.map { |found| found['hostmacroid'].to_i }).to eq([@base])
    end

    it 'get_full_data_global returns the global row, keyed by globalmacroid' do
      found = Live.retrying('get_full_data_global') { usermacros.get_full_data_global(macro: globally) }
      expect(found.map { |row| row['globalmacroid'].to_i }).to eq([@global])
    end

    it 'dump_by_id finds the host macro through the overridden key' do
      expect(Live.retrying('dump_by_id') { usermacros.dump_by_id(hostmacroid: @base) }.first['macro']).to eq(base)
    end

    it 'all lists host macros only, mapping the name to an Integer id' do
      table = Live.retrying('all') { usermacros.all }
      expect(table[base]).to be_a(Integer)
      expect([@base, @other]).to include(table[base])
      expect(table).not_to include(globally)
    end

    it 'get_raw passes documented parameters through: a select and a sortfield' do
      row = Live.retrying('get_raw select') { usermacros.get_raw(hostmacroids: [@base], output: %w[hostmacroid macro], selectHosts: 'extend') }.first
      expect(row['hosts'].map { |host| host['hostid'].to_i }).to eq([@h1])

      sorted = Live.retrying('get_raw sortfield') { usermacros.get_raw(hostids: [@h1], output: %w[macro], sortfield: 'macro') }.map { |found| found['macro'] }
      expect(sorted.size).to be > 1
      expect(sorted).to eq(sorted.sort)
    end
  end

  describe 'update' do
    it 'writes the fields it is given and leaves the macro name as it was' do
      created = Live.retrying('create updatable') { usermacros.create(hostid: @h1, macro: Live.macro(klass, 'updatable'), value: 'before') }
      expect(Live.retrying('update') { usermacros.update(hostmacroid: created, value: 'after', description: 'written by the spec') }).to eq(created)

      stored = Live.one('usermacro', hostmacroids: [created])
      expect([stored['value'], stored['description']]).to eq(['after', 'written by the spec'])
      expect(stored['macro']).to eq(Live.macro(klass, 'updatable'))
    end

    it 'returns the id again for data the object already carries' do
      expect(Live.retrying('update unchanged') { usermacros.update(hostmacroid: @base, value: 'v1') }).to eq(@base)
      expect(Live.one('usermacro', hostmacroids: [@base])['value']).to eq('v1')
    end

    it 'refuses the hostid' do
      expect { Live.retrying('update hostid') { usermacros.update(hostmacroid: @base, hostid: @h1, value: 'moved') } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*hostid/)
      expect(Live.one('usermacro', hostmacroids: [@base])['value']).to eq('v1')
    end

    it 'refuses a payload without a hostmacroid before it reaches the server' do
      # No Live.retrying: the guard raises locally, so there is no request to retry.
      expect { usermacros.update(value: 'orphan') }.to raise_error(ZabbixApi::ApiError, /hostmacroid not supplied in call to update/)
    end
  end

  describe 'update_global' do
    it 'writes the value and reads it back' do
      expect(Live.retrying('update_global') { usermacros.update_global(globalmacroid: @global, value: 'g1-updated') }).to eq(@global)
      expect(Live.raw('usermacro.get', globalmacro: true, globalmacroids: [@global], output: 'extend').first['value']).to eq('g1-updated')
    end

    it 'refuses a hostid' do
      expect { Live.retrying('update_global hostid') { usermacros.update_global(globalmacroid: @global, hostid: @h1, value: 'x') } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*hostid/)
    end

    it 'refuses a payload without a globalmacroid before it reaches the server' do
      # No Live.retrying: the guard raises locally, so there is no request to retry.
      expect { usermacros.update_global(value: 'orphan') }.to raise_error(ZabbixApi::ApiError, /globalmacroid not supplied in call to update_global/)
    end
  end

  describe 'the host-macro upserts' do
    it 'get_or_create returns the macro of that host and creates nothing' do
      expect(Live.retrying('get_or_create found') { usermacros.get_or_create(hostid: @h1, macro: base, value: 'ignored') }).to eq(@base)
      expect(Live.count('usermacro', hostids: [@h1], filter: { macro: base })).to eq(1)
      expect(Live.one('usermacro', hostmacroids: [@base])['value']).to eq('v1')
    end

    it 'get_or_create creates on the host it was scoped to when nothing matches' do
      created = Live.retrying('get_or_create create') { usermacros.get_or_create(hostid: @h1, macro: Live.macro(klass, 'goc'), value: 'v') }
      expect(Live.one('usermacro', hostmacroids: [created])['hostid'].to_i).to eq(@h1)
    end

    it 'create_or_update changes the existing macro of that host instead of duplicating it' do
      created = Live.retrying('create upsertable') { usermacros.create(hostid: @h1, macro: Live.macro(klass, 'upsertable'), value: 'before') }
      expect(Live.retrying('create_or_update') { usermacros.create_or_update(hostid: @h1, macro: Live.macro(klass, 'upsertable'), value: 'after') }).to eq(created)
      expect(Live.one('usermacro', hostmacroids: [created])['value']).to eq('after')
      expect(Live.count('usermacro', hostids: [@h1], filter: { macro: Live.macro(klass, 'upsertable') })).to eq(1)
    end

    it 'create_or_update creates when the host does not carry the macro yet' do
      created = Live.retrying('create_or_update create') { usermacros.create_or_update(hostid: @h1, macro: Live.macro(klass, 'cou'), value: 'v') }
      expect(Live.one('usermacro', hostmacroids: [created])['value']).to eq('v')
    end

    it 'scopes by host, so the same call against the other host creates a second macro' do
      first = Live.retrying('scoped h1') { usermacros.create_or_update(hostid: @h1, macro: Live.macro(klass, 'scoped'), value: 'one') }
      second = Live.retrying('scoped h2') { usermacros.create_or_update(hostid: @h2, macro: Live.macro(klass, 'scoped'), value: 'two') }
      expect(second).not_to eq(first)
      expect(Live.one('usermacro', hostmacroids: [first])['value']).to eq('one')
    end
  end

  describe 'the global upserts' do
    it 'get_or_create_global returns the existing macro although it was handed a hostid' do
      expect(Live.retrying('get_or_create_global found') { usermacros.get_or_create_global(macro: globally, value: 'ignored', hostid: @h1) }).to eq(@global)
    end

    it 'get_or_create_global creates without the hostid it was handed' do
      created = Live.owns('globalmacro', Live.retrying('get_or_create_global create') { usermacros.get_or_create_global(macro: Live.macro(klass, 'ggoc'), value: 'gv', hostid: @h1) }) { |id| Live.raw('usermacro.deleteglobal', [id]) }
      stored = Live.raw('usermacro.get', globalmacro: true, globalmacroids: [created], output: 'extend').first
      expect(stored['value']).to eq('gv')
      expect(stored).not_to have_key('hostid')
    end

    it 'create_or_update_global changes the existing global macro rather than duplicating it' do
      expect(Live.retrying('create_or_update_global') { usermacros.create_or_update_global(macro: globally, value: 'g-via-upsert', hostid: @h1) }).to eq(@global)
      expect(Live.raw('usermacro.get', globalmacro: true, globalmacroids: [@global], output: 'extend').first['value']).to eq('g-via-upsert')
      expect(Live.raw('usermacro.get', globalmacro: true, filter: { macro: globally }, output: %w[globalmacroid]).size).to eq(1)
    end

    it 'create_or_update_global creates when no global macro carries the name' do
      created = Live.owns('globalmacro', Live.retrying('create_or_update_global create') { usermacros.create_or_update_global(macro: Live.macro(klass, 'gcou'), value: 'gv') }) { |id| Live.raw('usermacro.deleteglobal', [id]) }
      expect(Live.raw('usermacro.get', globalmacro: true, globalmacroids: [created], output: 'extend').first['macro']).to eq(Live.macro(klass, 'gcou'))
    end
  end

  describe 'delete' do
    it 'removes the host macro and returns its id' do
      gone = Live.retrying('create gone') { usermacros.create(hostid: @h1, macro: Live.macro(klass, 'gone'), value: 'v') }
      expect(Live.retrying('delete') { usermacros.delete(gone) }).to eq(gone)
      expect(Live.get('usermacro', hostmacroids: [gone])).to eq([])
    end

    it 'removes the global macro and returns its id' do
      gone = Live.owns('globalmacro', Live.retrying('create ggone') { usermacros.create_global(macro: Live.macro(klass, 'ggone'), value: 'v') }) { |id| Live.raw('usermacro.deleteglobal', [id]) }
      expect(Live.retrying('delete_global') { usermacros.delete_global(gone) }).to eq(gone)
      Live.disown('globalmacro', gone)
      expect(Live.raw('usermacro.get', globalmacro: true, globalmacroids: [gone], output: %w[globalmacroid])).to eq([])
    end

    it 'refuses an id no macro of either kind carries' do
      expect { Live.retrying('delete absent') { usermacros.delete(999999999) } }.to raise_error(ZabbixApi::ApiError, /No permissions to referred object/)
      expect { Live.retrying('delete_global absent') { usermacros.delete_global(999999999) } }.to raise_error(ZabbixApi::ApiError, /No permissions to referred object/)
    end
  end

  describe 'macros on a template' do
    it 'stores a macro against a template id like any host macro, and linking does not copy it onto the host' do
      on_template = Live.macro(klass, 'tplmacro')
      created = Live.retrying('template macro') { usermacros.create(hostid: @template, macro: on_template, value: 'from-template') }
      expect(Live.one('usermacro', hostmacroids: [created])['hostid'].to_i).to eq(@template)

      Live.retrying('link') { Live.raw('host.update', hostid: @h2, templates: [{ templateid: @template }]) }
      expect(Live.count('usermacro', hostids: [@h2], filter: { macro: on_template })).to eq(0)
      expect(Live.count('usermacro', hostids: [@template], filter: { macro: on_template })).to eq(1)
    end
  end

  describe 'aftercare' do
    it 'leaves no host, template, host group, template group or global macro under its prefix once torn down, and the stock global macro {$SNMP_COMMUNITY}, the standing hosts and proxy still present' do
      Live.teardown

      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('template', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('templategroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.raw('usermacro.get', globalmacro: true, output: %w[globalmacroid macro], search: { macro: Live.macro_prefix(klass) })).to eq([])

      expect(Live.raw('usermacro.get', globalmacro: true, filter: { macro: '{$SNMP_COMMUNITY}' }, output: %w[macro]).size).to eq(1)
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
