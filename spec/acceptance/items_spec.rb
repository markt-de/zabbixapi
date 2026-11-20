# Contract: ZabbixApi::Items live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/item
#   classes:  the three-parameter create stores the class's defaults and leaves history and trends
#             to the server | a non-numeric value_type reads back trends 0, so no retention default
#             is invented | an interface-bound type is accepted with its interface and refused
#             without one | a zero-delay type stores delay 0, and an explicit delay is forwarded
#             into the server's refusal | a dependent item keeps its master and goes with it |
#             refusals: a key the caller omitted and a key another item on that host carries |
#             reads: by name across hosts, by name and host, absent, by id, raw, and the table |
#             update writes a batch, leaves an unchanged object alone, forces, replaces tags, and
#             is refused for hostid and for a read-only property | the four upsert branches, one of
#             them resolving to the other host | delete | a template item carries a uuid and needs
#             no interface, and the inherited copy refuses name and deletion but takes a
#             description | aftercare
#   not here: the hooks and the exact default_options, which the unit spec pins, as it pins the wire
#             shape of an omitted key_ - dropped, not nulled - on the request, while the server's
#             refusal of it is here; the remaining item types and the SNMP, IPMI and JMX interface
#             kinds, one accepted and one refused representative kept; the six value_types, one
#             non-numeric representative kept; binary, which only a dependent item accepts, and type
#             values outside the documented list, whose refusals are one class with the delay
#             refusal kept here; the get parameters and selects the gem only passes through, one
#             kept; web items, which need a web scenario to exist at all and whose create, update
#             and delete the server refuses; flags, never written: item.create accepts 4 but stores
#             0, and item.update refuses it as an unexpected parameter; a server-wide item count,
#             which anything else writing to the server moves
require 'spec_helper'

RSpec.describe 'ZabbixApi::Items live', type: :acceptance do
  klass = 'items'
  base_key = 'zbxapi.spec.items.base'
  tpl_key = 'zbxapi.spec.items.tplitem'

  before(:all) do
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'template')
    Live.preclean(klass, 'hostgroup')
    Live.preclean(klass, 'templategroup')

    @group = Live.owns('hostgroup', Live.retrying('hostgroup.create') { Live.session.hostgroups.create(name: Live.name(klass, 'hg')) })
    @tplgroup = Live.owns('templategroup', Live.retrying('templategroup.create') { Live.session.templategroups.create(name: Live.name(klass, 'tgrp')) })
    @template = Live.owns('template', Live.retrying('template.create') { Live.session.templates.create(host: Live.name(klass, 'tpl'), groups: [{ groupid: @tplgroup }]) })

    @h1 = Live.owns('host', Live.retrying('host.create h1') do
      Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: @group }],
                                interfaces: [{ type: 1, main: 1, useip: 1, ip: '127.0.0.1', dns: '', port: '10050' }])
    end)
    @h2 = Live.owns('host', Live.retrying('host.create h2') { Live.session.hosts.create(host: Live.name(klass, 'h2'), groups: [{ groupid: @group }]) })
    @interface = Live.one('host', hostids: [@h1], selectInterfaces: %w[interfaceid type])['interfaces'].first['interfaceid'].to_i

    @base = Live.retrying('item.create base') { Live.session.items.create(name: Live.name(klass, 'base'), key_: base_key, hostid: @h1) }
    @twin = Live.retrying('item.create twin') { Live.session.items.create(name: Live.name(klass, 'base'), key_: base_key, hostid: @h2, type: 2) }
    @tpl_item = Live.retrying('item.create tpl') { Live.session.items.create(name: Live.name(klass, 'tplitem'), key_: tpl_key, hostid: @template) }
    Live.retrying('link template') { Live.raw('host.update', hostid: @h2, templates: [{ templateid: @template }]) }
  end

  after(:all) { Live.teardown }

  let(:items) { Live.session.items }
  # The copy the link minted on h2, read by its key, since the link returns no id for it.
  let(:inherited) { Live.retrying('inherited item') { Live.one('item', hostids: [@h2], filter: { key_: tpl_key }) } }

  describe 'create' do
    it 'stores the class defaults for type, value_type, delay and status, and history 31d and trends 365d' do
      stored = Live.one('item', itemids: [@base])
      expect(stored['name']).to eq(Live.name(klass, 'base'))
      expect(stored['key_']).to eq(base_key)
      expect(stored.values_at('type', 'value_type', 'delay', 'status')).to eq(%w[7 3 60 0])
      expect(stored.values_at('history', 'trends')).to eq(%w[31d 365d])
    end

    it 'reads back history 31d and trends 0 for a non-numeric value_type' do
      item = Live.retrying('create character') { items.create(name: Live.name(klass, 'char'), key_: 'zbxapi.spec.items.char', hostid: @h1, value_type: 1) }
      stored = Live.one('item', itemids: [item])
      expect(stored['value_type']).to eq('1')
      expect(stored.values_at('history', 'trends')).to eq(%w[31d 0])
    end

    it 'accepts an interface-bound type when the caller names the interface' do
      item = Live.retrying('create agent') do
        items.create(name: Live.name(klass, 'agent'), key_: 'zbxapi.spec.items.agent', hostid: @h1, type: 0, delay: '1m', interfaceid: @interface)
      end
      stored = Live.one('item', itemids: [item])
      expect(stored['type']).to eq('0')
      expect(stored['interfaceid'].to_i).to eq(@interface)
    end

    it 'is refused for that type on a host that has no interface' do
      expect { Live.retrying('create noif') { items.create(name: Live.name(klass, 'noif'), key_: 'zbxapi.spec.items.noif', hostid: @h2, type: 0, delay: '1m') } }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/the parameter.*interfaceid.*is missing/) }
    end

    it 'stores delay 0 for a zero-delay type, which the caller never asked for' do
      item = Live.retrying('create trapper') { items.create(name: Live.name(klass, 'trap'), key_: 'zbxapi.spec.items.trap', hostid: @h1, type: 2) }
      expect(Live.one('item', itemids: [item])['delay']).to eq('0')
    end

    # That the value goes out untouched rather than being rewritten to 0 is asserted offline, on
    # the request; live, only the server's answer to it is observable.
    it 'is refused when the caller passes a delay for such a type' do
      expect { Live.retrying('create traptoo') { items.create(name: Live.name(klass, 'traptoo'), key_: 'zbxapi.spec.items.traptoo', hostid: @h1, type: 2, delay: '1m') } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/delay})
    end

    it 'creates a dependent item that keeps its master and needs no interface' do
      item = Live.retrying('create dependent') do
        items.create(name: Live.name(klass, 'dep'), key_: 'zbxapi.spec.items.dep', hostid: @h1, type: 18, master_itemid: @base)
      end
      stored = Live.one('item', itemids: [item])
      expect(stored['master_itemid'].to_i).to eq(@base)
      expect([stored['delay'], stored['interfaceid']]).to eq(%w[0 0])
    end

    # The placeholder key_: nil is dropped rather than sent as null, so this is the server's answer
    # to an absent property, not to a null one; the wire shape is the unit spec's.
    it 'refuses an item whose key the caller omitted' do
      expect { Live.retrying('create nokey') { items.create(name: Live.name(klass, 'nokey'), hostid: @h1) } }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(%r{/1.*the parameter.*key_.*is missing}) }
    end

    it 'is refused for a key another item on that host already carries' do
      expect { Live.retrying('create twinkey') { items.create(name: Live.name(klass, 'twinkey'), key_: base_key, hostid: @h1) } }
        .to raise_error(ZabbixApi::ApiError, /already exists/)
    end
  end

  describe 'reads' do
    it 'get_id without a hostid refuses, reporting two matches' do
      expect { Live.retrying('get_id') { items.get_id(name: Live.name(klass, 'base')) } }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 item objects, not one \(itemid /)
    end

    it "get_id with a hostid returns that host's item, and the other host's for the other id" do
      expect(Live.retrying('get_id h1') { items.get_id(name: Live.name(klass, 'base'), hostid: @h1) }).to eq(@base)
      expect(Live.retrying('get_id h2') { items.get_id(name: Live.name(klass, 'base'), hostid: @h2) }).to eq(@twin)
    end

    it 'get_id returns nil for a name no item carries' do
      expect(Live.retrying('get_id absent') { items.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_full_data by name spans both hosts' do
      found = Live.retrying('get_full_data') { items.get_full_data(name: Live.name(klass, 'base')) }
      expect(found.map { |item| item['itemid'].to_i }).to match_array([@base, @twin])
      expect(found.first).to include('uuid', 'trends', 'master_itemid')
    end

    it 'dump_by_id returns the one item of that id' do
      dumped = Live.retrying('dump_by_id') { items.dump_by_id(itemid: @base) }
      expect(dumped.map { |item| item['itemid'].to_i }).to eq([@base])
    end

    it 'get_raw passes a documented parameter through: a field list with hostids' do
      rows = Live.retrying('get_raw') { items.get_raw(hostids: [@h1], output: %w[itemid key_], filter: { key_: base_key }) }
      expect(rows.map { |item| item['key_'] }).to eq([base_key])
      expect(rows.first.keys).to match_array(%w[itemid key_])
    end

    it 'all maps the name to an Integer id and collapses the two hosts into one entry' do
      table = Live.retrying('all') { items.all }
      expect(table[Live.name(klass, 'base')]).to be_a(Integer)
      expect([@base, @twin]).to include(table[Live.name(klass, 'base')])
      expect(Live.count('item', filter: { name: Live.name(klass, 'base') })).to eq(2)
    end
  end

  describe 'update' do
    it 'writes several properties in one call and every one reads back' do
      expect(Live.retrying('update batch') { items.update(itemid: @base, description: 'spec one', delay: '2m', history: '2h', status: 1) }).to eq(@base)
      stored = Live.one('item', itemids: [@base])
      expect(stored.values_at('description', 'delay', 'history', 'status')).to eq(['spec one', '2m', '2h', '1'])
    end

    it 'returns the id and leaves the stored fields untouched when nothing differs' do
      fields = %w[name key_ type value_type delay history trends status description]
      before_state = Live.one('item', itemids: [@base]).slice(*fields)
      expect(Live.retrying('update unchanged') { items.update(itemid: @base, description: 'spec one') }).to eq(@base)
      expect(Live.one('item', itemids: [@base]).slice(*fields)).to eq(before_state)
    end

    it 'returns the id for a forced update, and the description reads back as sent' do
      expect(Live.retrying('update forced') { items.update({ itemid: @base, description: 'spec one' }, true) }).to eq(@base)
      expect(Live.one('item', itemids: [@base])['description']).to eq('spec one')
    end

    # Were the second call skipped as equal - it cannot be, since no extend read returns tags - the
    # first value would still be stored, so this also asserts that the second call is issued.
    it 'replaces the tags rather than merging them, and no extend read returns them' do
      Live.retrying('update tags') { items.update(itemid: @base, tags: [{ tag: 'zbxapi-spec', value: 'first' }]) }
      expect(Live.retrying('update tags again') { items.update(itemid: @base, tags: [{ tag: 'zbxapi-spec', value: klass }]) }).to eq(@base)
      expect(Live.one('item', itemids: [@base], selectTags: 'extend')['tags']).to eq([{ 'tag' => 'zbxapi-spec', 'value' => klass }])
      expect(Live.one('item', itemids: [@base])).not_to have_key('tags')
    end

    it 'is refused for the hostid as an unexpected parameter' do
      expect { Live.retrying('update hostid') { items.update(itemid: @base, hostid: @h1, description: 'hostid must not reach the update') } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter.*hostid/)
    end

    it 'is refused for a read-only property' do
      expect { Live.retrying('update templateid') { items.update(itemid: @base, templateid: 999999) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter.*templateid/)
    end
  end

  describe 'upserts' do
    it 'create_or_update changes the existing item of that name on that host without duplicating it' do
      expect(Live.retrying('upsert update') { items.create_or_update(name: Live.name(klass, 'base'), key_: base_key, hostid: @h1, description: 'upserted') }).to eq(@base)
      expect(Live.one('item', itemids: [@base])['description']).to eq('upserted')
      expect(Live.count('item', hostids: [@h1], filter: { name: Live.name(klass, 'base') })).to eq(1)
    end

    it 'create_or_update creates when that host has no item of the name' do
      created = Live.retrying('upsert create') { items.create_or_update(name: Live.name(klass, 'cou'), key_: 'zbxapi.spec.items.cou', hostid: @h1) }
      stored = Live.one('item', itemids: [created])
      expect(stored['name']).to eq(Live.name(klass, 'cou'))
      expect(stored['hostid'].to_i).to eq(@h1)
    end

    it 'get_or_create returns the existing id and creates nothing' do
      expect(Live.retrying('get_or_create found') { items.get_or_create(name: Live.name(klass, 'base'), hostid: @h1) }).to eq(@base)
      expect(Live.count('item', hostids: [@h1], filter: { name: Live.name(klass, 'base') })).to eq(1)
    end

    it 'get_or_create creates when that host has no item of the name' do
      created = Live.retrying('get_or_create create') { items.get_or_create(name: Live.name(klass, 'goc'), key_: 'zbxapi.spec.items.goc', hostid: @h1, type: 2) }
      expect(Live.one('item', itemids: [created])['name']).to eq(Live.name(klass, 'goc'))
    end

    it "get_or_create scoped to the other host resolves to that host's own item" do
      expect(Live.retrying('get_or_create twin') { items.get_or_create(name: Live.name(klass, 'base'), hostid: @h2) }).to eq(@twin)
    end
  end

  describe 'delete' do
    it 'removes the item and returns its id' do
      disposable = Live.retrying('create disposable') { items.create(name: Live.name(klass, 'disposable'), key_: 'zbxapi.spec.items.disposable', hostid: @h1) }
      expect(Live.retrying('delete') { items.delete(disposable) }).to eq(disposable)
      expect(Live.get('item', itemids: [disposable])).to eq([])
    end

    it 'takes the dependent item with its master, as the item.delete reference documents' do
      master = Live.retrying('create master') { items.create(name: Live.name(klass, 'master'), key_: 'zbxapi.spec.items.master', hostid: @h1, type: 2) }
      dependent = Live.retrying('create dep2') do
        items.create(name: Live.name(klass, 'dep2'), key_: 'zbxapi.spec.items.dep2', hostid: @h1, type: 18, master_itemid: master)
      end
      expect(Live.retrying('delete master') { items.delete(master) }).to eq(master)
      expect(Live.get('item', itemids: [dependent])).to eq([])
    end

    it 'is refused for an id no item carries' do
      expect { Live.retrying('delete absent') { items.delete(999999999) } }.to raise_error(ZabbixApi::ApiError, /does not exist/)
    end
  end

  describe 'a template item and the copy it was inherited into' do
    it 'needs no interface and carries a uuid the host item lacks' do
      stored = Live.one('item', itemids: [@tpl_item])
      expect(stored['interfaceid']).to eq('0')
      expect(stored['uuid']).to match(/\A[0-9a-f]{32}\z/)
      expect(Live.one('item', itemids: [@base])['uuid']).to eq('')
    end

    it 'was copied onto the linked host, the copy pointing at the template item' do
      expect(inherited['templateid'].to_i).to eq(@tpl_item)
    end

    it 'refuses a name change on the copy' do
      expect { Live.retrying('update inherited name') { items.update(itemid: inherited['itemid'].to_i, name: Live.name(klass, 'renamed')) } }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/cannot update readonly parameter.*name.*of inherited object/) }
    end

    it 'refuses to delete the copy directly' do
      expect { Live.retrying('delete inherited') { items.delete(inherited['itemid'].to_i) } }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(%r{/1.*cannot delete inherited item}) }
    end

    it 'takes a description on the copy, which is writable' do
      id = inherited['itemid'].to_i
      expect(Live.retrying('update inherited') { items.update(itemid: id, description: 'spec inherited') }).to eq(id)
      expect(Live.one('item', itemids: [id])['description']).to eq('spec inherited')
    end
  end

  describe 'aftercare' do
    it 'leaves no host, template, host group or template group under its prefix once torn down, and the standing hosts and proxy still present' do
      Live.teardown
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('template', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('templategroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
