# Contract: ZabbixApi::ValueMaps live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/valuemap
#   classes:  create stores hostid, name and the mappings, and output extend answers with hostid and
#             uuid where the valuemap.get reference's example shows neither | refusals: each
#             required property, an empty mappings array, a type outside the enum, a type 5 mapping
#             carrying a value, a uuid on a host's map | a string-keyed payload reaches the server |
#             the same name on a second host, which is what the hostid scope exists for | reads: the
#             scoped and the unscoped lookup, the blind-lookup guards, the undocumented hostids
#             parameter, one selectMappings form per return shape, one sortfield, all by membership
#             | update: rename, mappings replace, an unchanged and a forced update leave the object
#             alone, the constant hostid is refused, no id refuses locally | the four upsert
#             branches and the string-keyed one | a template's map is given a uuid, is not copied to
#             a linked host, and keeps its name through an update passing only a changed uuid
#             (pending) | delete removes, is refused for an unknown id, and is allowed while an item
#             references the map, the item's valuemapid falling back to 0 | aftercare
#   not here: the hooks, and the wire shapes of the reads, the updates and the upserts, which the
#             unit spec asserts offline; that an unchanged update sends no request, visible only in
#             the traffic and asserted offline; mapping types 1 to 4 carrying a value, type 0 kept
#             as the representative of a mapping that carries one; their refusal of an omitted
#             value, the same for all four: `the parameter "value" is missing.`, and of an empty
#             one: `a floating point value is expected.` for types 1 and 2, `cannot be empty.` for
#             types 3 and 4; uuid on update, which the server validates as on create - a host's map
#             refuses one, a template's takes a new UUIDv4 - the create refusal kept as the
#             representative, while a changed uuid sent without a name, which empties a template
#             map's name in the pending example, fails on a second map of that template with
#             `SQL statement execution has failed`, a server defect no example pins; the user type
#             create, update and delete require, which needs a second user: an Admin user with
#             read-write on the host's group may call all three, though their references name Super
#             admin alone, and is refused all three for a host whose group it may only read or has
#             no rights on, with `No permissions to referred object or it does not exist!`, the
#             message an absent id draws; a template value map an item uses, which linking copies to
#             the host no more than an unused one, the inherited item keeping the template's
#             valuemapid - the unused map kept as the representative; server-wide counts and the
#             size of `all`, which anything else writing to the server moves
require 'spec_helper'
require 'securerandom'

RSpec.describe 'ZabbixApi::ValueMaps live', type: :acceptance do
  klass = 'valuemaps'
  mapping = [{ type: 0, value: '1', newvalue: 'Up' }].freeze
  two_mappings = [{ type: 0, value: '0', newvalue: 'Offline' }, { type: 0, value: '1', newvalue: 'Online' }].freeze

  # A real UUIDv4 without its dashes, the only form the server takes where it takes one at all.
  def uuid4
    SecureRandom.uuid.delete('-')
  end

  def stored(id, extra = {})
    Live.one('valuemap', { valuemapids: [id] }.merge(extra))
  end

  def mappings_of(id)
    stored(id, selectMappings: 'extend')['mappings']
  end

  before(:all) do
    # Containers only, and hosts and templates before their groups: a group that is a host's only
    # group cannot be deleted. Value maps are contents and are never pre-cleaned by name.
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'template')
    Live.preclean(klass, 'hostgroup')
    Live.preclean(klass, 'templategroup')

    @group = Live.owns('hostgroup', Live.retrying('create group') { Live.session.hostgroups.create(name: Live.name(klass, 'grp')) })
    @tgroup = Live.owns('templategroup', Live.retrying('create template group') { Live.session.templategroups.create(name: Live.name(klass, 'tgrp')) })
    @h1 = Live.owns('host', Live.retrying('create h1') { Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: @group }], status: 1) })
    @h2 = Live.owns('host', Live.retrying('create h2') { Live.session.hosts.create(host: Live.name(klass, 'h2'), groups: [{ groupid: @group }], status: 1) })
    @tpl = Live.owns('template', Live.retrying('create template') { Live.session.templates.create(host: Live.name(klass, 'tpl'), groups: [{ groupid: @tgroup }]) })

    @base = Live.retrying('create base') { Live.session.valuemaps.create(hostid: @h1, name: Live.name(klass, 'base'), mappings: mapping) }
    @twin = Live.retrying('create twin') { Live.session.valuemaps.create(hostid: @h2, name: Live.name(klass, 'base'), mappings: mapping) }
    @tplmap = Live.retrying('create tplmap') { Live.session.valuemaps.create(hostid: @tpl, name: Live.name(klass, 'tplmap'), mappings: mapping) }
  end

  after(:all) do
    Live.teardown
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'template')
    Live.preclean(klass, 'hostgroup')
    Live.preclean(klass, 'templategroup')
  end

  let(:valuemaps) { Live.session.valuemaps }

  describe 'create' do
    it 'stores the map on the host it named, with the mapping it was given' do
      row = stored(@base, selectMappings: 'extend')
      expect(row['name']).to eq(Live.name(klass, 'base'))
      expect(row['hostid'].to_i).to eq(@h1)
      expect(row['mappings']).to eq([{ 'type' => '0', 'value' => '1', 'newvalue' => 'Up' }])
    end

    it "answers output extend with hostid and uuid, which the valuemap.get reference's example omits, and a host's map carries no uuid" do
      row = stored(@base)
      expect(row.keys).to include('hostid', 'uuid')
      expect(row['uuid']).to eq('')
    end

    it 'refuses a payload missing any one of hostid, name and mappings' do
      full = { hostid: @h1, name: Live.name(klass, 'incomplete'), mappings: mapping }
      [:hostid, :name, :mappings].each do |property|
        expect { Live.retrying("create without #{property}") { valuemaps.create(full.reject { |field, _| field == property }) } }
          .to raise_error(ZabbixApi::ApiError, /the parameter .*#{property}.* is missing/)
      end
    end

    it 'refuses an empty mappings array' do
      expect { Live.retrying('create empty mappings') { valuemaps.create(hostid: @h1, name: Live.name(klass, 'emptymap'), mappings: []) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/mappings.*cannot be empty})
    end

    it 'refuses a mapping type outside the enum the valuemap object reference documents' do
      expect { Live.retrying('create bad type') { valuemaps.create(hostid: @h1, name: Live.name(klass, 'badtype'), mappings: [{ type: 6, value: '1', newvalue: 'x' }]) } }
        .to raise_error(ZabbixApi::ApiError, /value must be one of 0, 1, 2, 3, 4, 5/)
    end

    it 'refuses a mapping without a newvalue' do
      expect { Live.retrying('create no newvalue') { valuemaps.create(hostid: @h1, name: Live.name(klass, 'nonewvalue'), mappings: [{ type: 0, value: '1' }]) } }
        .to raise_error(ZabbixApi::ApiError, /the parameter .*newvalue.* is missing/)
    end

    it 'refuses a type 5 mapping that carries a value, siding with the type description of the valuemap object reference' do
      expect { Live.retrying('create type 5 with value') { valuemaps.create(hostid: @h1, name: Live.name(klass, 'ty5value'), mappings: [{ type: 5, value: 'x', newvalue: 'Default' }]) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/mappings/1/value.*should be empty})
    end

    it "accepts a type 0 mapping whose value is empty, where the valuemap object reference's type description says it cannot be" do
      empty = Live.retrying('create type 0 empty value') { valuemaps.create(hostid: @h1, name: Live.name(klass, 'ty0empty'), mappings: [{ type: 0, value: '', newvalue: 'x' }]) }
      expect(mappings_of(empty)).to eq([{ 'type' => '0', 'value' => '', 'newvalue' => 'x' }])
    end

    it 'refuses a uuid on a host value map' do
      expect { Live.retrying('create host uuid') { valuemaps.create(hostid: @h1, name: Live.name(klass, 'uuid'), mappings: mapping, uuid: uuid4) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/uuid.*value must be empty})
    end

    it 'accepts a string-keyed payload and stores the name it carried' do
      id = Live.retrying('create strings') { valuemaps.create('hostid' => @h1, 'name' => Live.name(klass, 'strings'), 'mappings' => [{ 'type' => 0, 'value' => '1', 'newvalue' => 'Up' }]) }
      expect(stored(id)['name']).to eq(Live.name(klass, 'strings'))
    end

    it 'lets a second host carry the same name' do
      expect(stored(@twin)['hostid'].to_i).to eq(@h2)
      expect(Live.count('valuemap', filter: { name: Live.name(klass, 'base') })).to eq(2)
    end
  end

  describe 'reads' do
    it 'get_id scoped by hostid returns the map of that host, and the other host has its own' do
      expect(Live.retrying('get_id h1') { valuemaps.get_id(name: Live.name(klass, 'base'), hostid: @h1) }).to eq(@base)
      expect(Live.retrying('get_id h2') { valuemaps.get_id(name: Live.name(klass, 'base'), hostid: @h2) }).to eq(@twin)
    end

    it 'get_id without a hostid refuses, reporting two matches' do
      expect { Live.retrying('get_id unscoped') { valuemaps.get_id(name: Live.name(klass, 'base')) } }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 valuemap objects, not one \(valuemapid /)
    end

    it 'get_id returns nil for a name no value map carries' do
      expect(Live.retrying('get_id absent') { valuemaps.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_id refuses to run blind' do
      expect { valuemaps.get_id({}) }.to raise_error(ZabbixApi::ApiError, /name not supplied/)
    end

    it 'get_full_data spans hosts' do
      found = Live.retrying('get_full_data') { valuemaps.get_full_data(name: Live.name(klass, 'base')) }
      expect(found.map { |row| row['valuemapid'].to_i }).to match_array([@base, @twin])
    end

    it 'dump_by_id returns the one map of that id' do
      expect(Live.retrying('dump_by_id') { valuemaps.dump_by_id(valuemapid: @base) }.map { |row| row['valuemapid'].to_i }).to eq([@base])
    end

    it 'dump_by_id refuses to run blind' do
      expect { valuemaps.dump_by_id({}) }.to raise_error(ZabbixApi::ApiError, /valuemapid not supplied/)
    end

    it 'get_raw scopes by the hostids parameter, which the valuemap.get reference does not list' do
      rows = Live.retrying('get_raw hostids') { valuemaps.get_raw(hostids: [@h2], output: %w[valuemapid name]) }
      expect(rows.map { |row| row['valuemapid'].to_i }).to eq([@twin])
    end

    it 'get_raw returns the mappings under selectMappings extend and a String count under its count form' do
      expect(Live.retrying('selectMappings extend') { valuemaps.get_raw(valuemapids: [@base], selectMappings: 'extend') }.first['mappings'].size).to eq(1)
      expect(Live.retrying('selectMappings count') { valuemaps.get_raw(valuemapids: [@base], selectMappings: 'count') }.first['mappings']).to eq('1')
    end

    it 'get_raw sorts by name, one of the two sortfields the valuemap.get reference documents' do
      rows = Live.retrying('sortfield name') { valuemaps.get_raw(valuemapids: [@tplmap, @base], output: %w[valuemapid name], sortfield: 'name', sortorder: 'ASC') }
      expect(rows.map { |row| row['name'] }).to eq([Live.name(klass, 'base'), Live.name(klass, 'tplmap')])
    end

    it 'all answers with the repeated name mapped to one of the two ids, as an Integer' do
      table = Live.retrying('all') { valuemaps.all }
      expect([@base, @twin]).to include(table[Live.name(klass, 'base')])
    end
  end

  describe 'update' do
    it 'renames the map and the new name reads back' do
      id = Live.retrying('create renamable') { valuemaps.create(hostid: @h1, name: Live.name(klass, 'renamable'), mappings: mapping) }
      expect(Live.retrying('update name') { valuemaps.update(valuemapid: id, name: Live.name(klass, 'renamed')) }).to eq(id)
      expect(stored(id)['name']).to eq(Live.name(klass, 'renamed'))
    end

    it 'replaces the mappings' do
      id = Live.retrying('create remappable') { valuemaps.create(hostid: @h1, name: Live.name(klass, 'remappable'), mappings: mapping) }
      Live.retrying('update mappings') { valuemaps.update(valuemapid: id, mappings: two_mappings) }
      expect(mappings_of(id).map { |row| row['newvalue'] }).to match_array(%w[Offline Online])
    end

    it 'returns the id and leaves the map exactly as it was when nothing differs' do
      before_state = stored(@base)
      expect(Live.retrying('update unchanged') { valuemaps.update(valuemapid: @base, name: Live.name(klass, 'base')) }).to eq(@base)
      expect(stored(@base)).to eq(before_state)
    end

    it 'returns the id for a forced update, and the name reads back as sent' do
      expect(Live.retrying('update forced') { valuemaps.update({ valuemapid: @base, name: Live.name(klass, 'base') }, true) }).to eq(@base)
      expect(stored(@base)['name']).to eq(Live.name(klass, 'base'))
    end

    it 'is refused a hostid, which is constant, and the map stays on its host' do
      expect { Live.retrying('update hostid') { valuemaps.update(valuemapid: @base, hostid: @h2, name: Live.name(klass, 'moved')) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*hostid/)
      row = stored(@base)
      expect([row['hostid'].to_i, row['name']]).to eq([@h1, Live.name(klass, 'base')])
    end

    it 'raises when no valuemapid says which map to write' do
      expect { valuemaps.update(name: Live.name(klass, 'base')) }.to raise_error(ZabbixApi::ApiError, /valuemapid not supplied/)
    end
  end

  describe 'upserts' do
    it 'create_or_update updates the map of that name on that host, leaving one map of the name there' do
      expect(Live.retrying('upsert update') { valuemaps.create_or_update(hostid: @h1, name: Live.name(klass, 'base'), mappings: two_mappings) }).to eq(@base)
      expect(mappings_of(@base).size).to eq(2)
      expect(Live.count('valuemap', filter: { name: Live.name(klass, 'base'), hostid: @h1 })).to eq(1)
    end

    it 'create_or_update takes the update branch for a string-keyed payload too' do
      expect(Live.retrying('upsert strings') { valuemaps.create_or_update('hostid' => @h1, 'name' => Live.name(klass, 'base'), 'mappings' => [{ 'type' => 0, 'value' => '1', 'newvalue' => 'Up' }]) }).to eq(@base)
      expect(mappings_of(@base)).to eq([{ 'type' => '0', 'value' => '1', 'newvalue' => 'Up' }])
    end

    it 'create_or_update creates on the host it was given when no map of that name is there' do
      id = Live.retrying('upsert create') { valuemaps.create_or_update(hostid: @h2, name: Live.name(klass, 'upserted'), mappings: mapping) }
      expect(stored(id)['hostid'].to_i).to eq(@h2)
    end

    it 'get_or_create returns the id of the scoped map and creates nothing' do
      expect(Live.retrying('get_or_create found') { valuemaps.get_or_create(hostid: @h2, name: Live.name(klass, 'base'), mappings: mapping) }).to eq(@twin)
      expect(Live.count('valuemap', filter: { name: Live.name(klass, 'base'), hostid: @h2 })).to eq(1)
    end

    it 'get_or_create creates when the host carries no map of that name' do
      id = Live.retrying('get_or_create create') { valuemaps.get_or_create(hostid: @h1, name: Live.name(klass, 'gotten'), mappings: mapping) }
      expect(stored(id)['name']).to eq(Live.name(klass, 'gotten'))
    end
  end

  describe 'a value map on a template' do
    it 'is given a uuid the server mints' do
      expect(stored(@tplmap)['uuid']).to match(/\A[0-9a-f]{32}\z/)
    end

    it 'is not copied to a host the template is linked to while no item references it' do
      Live.retrying('link template') { Live.raw('host.update', hostid: @h2, templates: [{ templateid: @tpl }]) }
      linked = Live.one('host', hostids: [@h2], selectParentTemplates: %w[templateid])['parentTemplates']
      expect(linked.map { |template| template['templateid'].to_i }).to eq([@tpl])
      expect(Live.get('valuemap', filter: { name: Live.name(klass, 'tplmap'), hostid: @h2 })).to eq([])
    end

    it 'keeps its name through an update passing only a changed uuid, as the valuemap.update reference says of every property not passed' do
      pending 'a changed uuid sent without a name empties the name of a template value map'
      template = Live.owns('template', Live.retrying('create uuid template') { Live.session.templates.create(host: Live.name(klass, 'uuidtpl'), groups: [{ groupid: @tgroup }]) })
      id = Live.retrying('create uuidname') { valuemaps.create(hostid: template, name: Live.name(klass, 'uuidname'), mappings: mapping) }
      sent = uuid4
      Live.retrying('update uuid alone') { valuemaps.update(valuemapid: id, uuid: sent) }
      expect(stored(id).values_at('uuid', 'name')).to eq([sent, Live.name(klass, 'uuidname')])
    end
  end

  describe 'delete' do
    it 'removes the map and returns its id' do
      id = Live.retrying('create disposable') { valuemaps.create(hostid: @h1, name: Live.name(klass, 'disposable'), mappings: mapping) }
      expect(Live.retrying('delete') { valuemaps.delete(id) }).to eq(id)
      expect(Live.get('valuemap', valuemapids: [id])).to eq([])
    end

    it 'is refused an id no value map carries' do
      expect { Live.retrying('delete unknown') { valuemaps.delete(999999999) } }
        .to raise_error(ZabbixApi::ApiError, /No permissions to referred object or it does not exist/)
    end

    it 'is allowed while an item references the map, and the item falls back to valuemapid 0' do
      used = Live.retrying('create used') { valuemaps.create(hostid: @h1, name: Live.name(klass, 'used'), mappings: mapping) }
      item = Live.retrying('create item') do
        Live.session.items.create(name: Live.name(klass, 'item'), key_: 'zbxapi.spec.valuemaps', hostid: @h1, type: 2, value_type: 3, valuemapid: used)
      end
      expect(Live.one('item', itemids: [item])['valuemapid'].to_i).to eq(used)

      expect(Live.retrying('delete used') { valuemaps.delete(used) }).to eq(used)
      expect(Live.one('item', itemids: [item])['valuemapid']).to eq('0')
    end
  end

  describe 'aftercare' do
    it 'leaves no host, template, host group or template group under its prefix once torn down, and the standing hosts and proxy and the stock host group still present' do
      Live.teardown
      %w[host template].each { |object| expect(Live.get(object, search: { host: Live.prefix(klass) })).to eq([]) }
      %w[hostgroup templategroup].each { |object| expect(Live.get(object, search: { name: Live.prefix(klass) })).to eq([]) }
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
      expect(Live.one('hostgroup', filter: { name: Live::GROUP_NAME })['name']).to eq(Live::GROUP_NAME)
    end
  end
end
