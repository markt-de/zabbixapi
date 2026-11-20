# Contract: ZabbixApi::Templates live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/template
#   classes:  create stores the technical name and defaults the visible one to it | the full
#             documented parameter set reads back, template link included | refusals: missing
#             groups, a host group where a template group is required, a duplicate name, half a
#             vendor pair | dump_by_id finds through templateids where a templateid filter finds
#             nothing | get_ids_by_host both input shapes and both blind refusals | reads by name,
#             by id, one get_raw select, all as membership | update writes, leaves an equal object
#             alone, forces, lands a collection, takes vendor_version alone, refuses without an id |
#             mass_add adds and links, mass_update replaces, mass_remove removes and clears, and
#             mass_add and mass_remove each refuse a key they cannot forward | the four upsert
#             branches | the three aliases | delete | aftercare
#   not here: the hooks, and the requests dump_by_id, get_ids_by_host and the mass_* methods build,
#             which are the unit spec's; the delete refused while an action references the template,
#             which would need this spec to create an action - an action acts on real events once
#             enabled; bulk arrays, which Basic#create and #delete handle and Basic's own spec
#             covers; a create without host, refused in the same form as the create without groups
#             kept here: `Invalid parameter "/1": the parameter "host" is missing.`
require 'spec_helper'
require 'securerandom'

RSpec.describe 'ZabbixApi::Templates live', type: :acceptance do
  klass = 'templates'

  before(:all) do
    # Templates before template groups: a group holding a template that belongs to it alone stays.
    Live.preclean(klass, 'template')
    Live.preclean(klass, 'templategroup')
    @tg1 = Live.owns('templategroup', Live.retrying('create grp1') { Live.session.templategroups.create(name: Live.name(klass, 'grp1')) })
    @tg2 = Live.owns('templategroup', Live.retrying('create grp2') { Live.session.templategroups.create(name: Live.name(klass, 'grp2')) })
    @one = Live.owns('template', Live.retrying('create one') { Live.session.templates.create(host: Live.name(klass, 'one'), groups: [{ groupid: @tg1 }]) })
  end

  after(:all) { Live.teardown }

  let(:templates) { Live.session.templates }

  describe 'create' do
    it 'stores the technical name, defaults the visible name to it and lets the server mint the uuid' do
      stored = Live.one('template', templateids: [@one])
      expect(stored['host']).to eq(Live.name(klass, 'one'))
      expect(stored['name']).to eq(Live.name(klass, 'one'))
      expect(stored['templateid'].to_i).to eq(@one)
      expect([stored['description'], stored['vendor_name'], stored['vendor_version']]).to eq(['', '', ''])
      expect(stored['uuid']).to match(/\A[0-9a-f]{32}\z/)
    end

    it 'stores every documented property besides the technical name and links the template its templates parameter names' do
      uuid = SecureRandom.uuid.delete('-')
      full = Live.owns('template', Live.retrying('create full') do
        templates.create(host: Live.name(klass, 'full'), name: Live.name(klass, 'full', 'visible'), description: 'spec fixture',
                         uuid: uuid, vendor_name: 'markt.de', vendor_version: '1.0',
                         groups: [{ groupid: @tg1 }, { groupid: @tg2 }],
                         tags: [{ tag: 'zbxapi-spec', value: klass }],
                         macros: [{ macro: Live.macro(klass, 'a'), value: 'aaa' }],
                         templates: [{ templateid: @one }])
      end)

      stored = Live.one('template', templateids: [full], selectTemplateGroups: %w[groupid], selectTags: %w[tag value],
                                    selectMacros: %w[macro value], selectParentTemplates: %w[templateid])
      expect(stored['name']).to eq(Live.name(klass, 'full', 'visible'))
      expect(stored['description']).to eq('spec fixture')
      expect(stored['uuid']).to eq(uuid)
      expect([stored['vendor_name'], stored['vendor_version']]).to eq(['markt.de', '1.0'])
      expect(stored['templategroups'].map { |templategroup| templategroup['groupid'].to_i }).to match_array([@tg1, @tg2])
      expect(stored['tags']).to eq([{ 'tag' => 'zbxapi-spec', 'value' => klass }])
      expect(stored['macros'].map { |item| [item['macro'], item['value']] }).to eq([[Live.macro(klass, 'a'), 'aaa']])
      expect(stored['parentTemplates'].map { |parent| parent['templateid'].to_i }).to eq([@one])
    end

    it 'refuses a create without the required groups' do
      expect { Live.retrying('create nogroups') { templates.create(host: Live.name(klass, 'nogroups')) } }.to raise_error(ZabbixApi::ApiError, /the parameter .*groups.* is missing/)
    end

    # Refused with code -32500, Application error.: Invalid parameter "/1/groups/1": object does not
    # exist, or you have no permissions to it.
    it 'refuses a host group where a template group is required, naming the element that was wrong' do
      hostgroup = Live.one('hostgroup', filter: { name: Live::GROUP_NAME })['groupid'].to_i
      expect { Live.retrying('create hostgroup') { templates.create(host: Live.name(klass, 'hostgroup'), groups: [{ groupid: hostgroup }]) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/groups/1.*object does not exist, or you have no permissions to it})
    end

    it 'refuses a technical name another template already carries' do
      expect { Live.retrying('create duplicate') { templates.create(host: Live.name(klass, 'one'), groups: [{ groupid: @tg1 }]) } }
        .to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses vendor_name without vendor_version' do
      expect { Live.retrying('create vendor') { templates.create(host: Live.name(klass, 'vendor'), groups: [{ groupid: @tg1 }], vendor_name: 'markt.de') } }
        .to raise_error(ZabbixApi::ApiError, /both vendor_name and vendor_version should be either present or empty/)
    end
  end

  describe 'dump_by_id' do
    it 'finds the template by its id' do
      dumped = Live.retrying('dump_by_id') { templates.dump_by_id(templateid: @one) }
      expect(dumped.map { |template| template['host'] }).to eq([Live.name(klass, 'one')])
    end

    # Templates are stored in the hosts table, so a filter on templateid matches nothing.
    it 'finds nothing through a filter on its own id' do
      expect(Live.raw('template.get', filter: { templateid: @one }, output: ['host'])).to eq([])
    end
  end

  describe 'get_ids_by_host' do
    it 'returns the id of the template a bare host value names' do
      expect(Live.retrying('by host') { templates.get_ids_by_host(host: Live.name(klass, 'one')) }).to eq([@one])
    end

    it 'returns the same id for a templateids parameter hash' do
      expect(Live.retrying('by templateids') { templates.get_ids_by_host(templateids: [@one]) }).to eq([@one])
    end

    it 'refuses an empty hash and a nil host' do
      expect { templates.get_ids_by_host({}) }.to raise_error(ZabbixApi::ApiError, /no parameters supplied in call to get_ids_by_host/)
      expect { templates.get_ids_by_host(host: nil) }.to raise_error(ZabbixApi::ApiError, /host not supplied in call to get_ids_by_host/)
    end
  end

  describe 'reads' do
    it 'get_id returns the id stored under that technical name' do
      expect(Live.retrying('get_id') { templates.get_id(host: Live.name(klass, 'one')) }).to eq(@one)
    end

    it 'get_id returns nil for a name no template carries' do
      expect(Live.retrying('get_id absent') { templates.get_id(host: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_full_data returns the template under its technical name with uuid, vendor_name and vendor_version' do
      found = Live.retrying('get_full_data') { templates.get_full_data(host: Live.name(klass, 'one')) }
      expect(found.map { |template| template['templateid'].to_i }).to eq([@one])
      expect(found.first).to include('uuid', 'vendor_name', 'vendor_version')
    end

    it 'get_raw passes a documented parameter through: selectTemplateGroups' do
      row = Live.retrying('get_raw') { templates.get_raw(output: ['host'], templateids: [@one], selectTemplateGroups: %w[groupid]) }.first
      expect(row['templategroups'].map { |templategroup| templategroup['groupid'].to_i }).to eq([@tg1])
    end

    it 'all maps the technical name of this template to its Integer id and holds the stock template' do
      table = Live.retrying('all') { templates.all }
      expect(table[Live.name(klass, 'one')]).to eq(@one)
      expect(table).to include(Live::TEMPLATE_NAME)
    end
  end

  describe 'update' do
    it 'writes two properties in one call and both read back' do
      target = Live.owns('template', Live.retrying('create renamable') { templates.create(host: Live.name(klass, 'renamable'), groups: [{ groupid: @tg1 }]) })
      expect(Live.retrying('update') { templates.update(templateid: target, description: 'desc v1', name: Live.name(klass, 'renamable', 'visible')) }).to eq(target)
      stored = Live.one('template', templateids: [target])
      expect([stored['description'], stored['name']]).to eq(['desc v1', Live.name(klass, 'renamable', 'visible')])
    end

    it 'returns the id and leaves the object exactly as it was when nothing differs' do
      before_state = Live.one('template', templateids: [@one])
      expect(Live.retrying('update unchanged') { templates.update(templateid: @one, host: Live.name(klass, 'one')) }).to eq(@one)
      expect(Live.one('template', templateids: [@one])).to eq(before_state)
    end

    it 'returns the id for a forced update, and the host reads back as sent' do
      expect(Live.retrying('update forced') { templates.update({ templateid: @one, host: Live.name(klass, 'one') }, true) }).to eq(@one)
      expect(Live.one('template', templateids: [@one])['host']).to eq(Live.name(klass, 'one'))
    end

    it 'returns the id for a macro update, and the macro reads back as sent' do
      target = Live.owns('template', Live.retrying('create macroed') { templates.create(host: Live.name(klass, 'macroed'), groups: [{ groupid: @tg1 }]) })
      expect(Live.retrying('update macros') { templates.update(templateid: target, macros: [{ macro: Live.macro(klass, 'b'), value: 'bbb' }]) }).to eq(target)
      stored = Live.one('template', templateids: [target], selectMacros: %w[macro value])
      expect(stored['macros'].map { |item| [item['macro'], item['value']] }).to eq([[Live.macro(klass, 'b'), 'bbb']])
    end

    it 'takes vendor_version alone once vendor_name is stored' do
      target = Live.owns('template', Live.retrying('create vendored') do
        templates.create(host: Live.name(klass, 'vendored'), groups: [{ groupid: @tg1 }], vendor_name: 'markt.de', vendor_version: '1.0')
      end)
      expect(Live.retrying('update vendor') { templates.update(templateid: target, vendor_version: '2.0') }).to eq(target)
      expect(Live.one('template', templateids: [target])['vendor_version']).to eq('2.0')
    end

    it 'refuses an update that names no templateid' do
      expect { templates.update(description: 'desc v1') }.to raise_error(ZabbixApi::ApiError, /templateid not supplied in call to dump_by_id/)
    end
  end

  describe 'the mass_* family' do
    before(:all) do
      @massed = Live.owns('template', Live.retrying('create massed') { Live.session.templates.create(host: Live.name(klass, 'massed'), groups: [{ groupid: @tg1 }]) })
      @linkable = Live.owns('template', Live.retrying('create linkable') { Live.session.templates.create(host: Live.name(klass, 'linkable'), groups: [{ groupid: @tg1 }]) })
    end

    it 'mass_add puts the template into a second group and adds a macro, both of which read back' do
      expect(Live.retrying('mass_add') { templates.mass_add(templates_id: [@massed], groups_id: [@tg2], macros: [{ macro: Live.macro(klass, 'c'), value: 'ccc' }]) }).to be(true)
      stored = Live.one('template', templateids: [@massed], selectTemplateGroups: %w[groupid], selectMacros: %w[macro value])
      expect(stored['templategroups'].map { |templategroup| templategroup['groupid'].to_i }).to match_array([@tg1, @tg2])
      expect(stored['macros'].map { |item| item['macro'] }).to eq([Live.macro(klass, 'c')])
    end

    # Linked and cleared in one example so the template is left as it was found, whatever order
    # RSpec runs this file in.
    it 'mass_add links what templates_link_id names, and mass_remove clears it again' do
      expect(Live.retrying('mass_add link') { templates.mass_add(templates_id: [@massed], templates_link_id: [@linkable]) }).to be(true)
      linked = Live.one('template', templateids: [@massed], selectParentTemplates: %w[templateid])
      expect(linked['parentTemplates'].map { |parent| parent['templateid'].to_i }).to eq([@linkable])

      expect(Live.retrying('mass_remove clear') { templates.mass_remove(templates_id: [@massed], templates_clear_id: [@linkable]) }).to be(true)
      cleared = Live.one('template', templateids: [@massed], selectParentTemplates: %w[templateid])
      expect(cleared['parentTemplates']).to eq([])
    end

    it 'mass_add refuses the API spelling templates_link, which is not a wrapper parameter' do
      expect { templates.mass_add(templates_id: [@massed], templates_link: [{ templateid: @linkable }]) }
        .to raise_error(ZabbixApi::ApiError, /unknown parameter templates_link in call to mass_add/)
    end

    it 'mass_update replaces the groups and the macros instead of adding to them' do
      expect(Live.retrying('mass_add before update') { templates.mass_add(templates_id: [@massed], groups_id: [@tg2], macros: [{ macro: Live.macro(klass, 'f'), value: 'fff' }]) }).to be(true)
      expect(Live.retrying('mass_update') { templates.mass_update(templates_id: [@massed], groups_id: [@tg1], macros: [{ macro: Live.macro(klass, 'd'), value: 'ddd' }]) }).to be(true)
      stored = Live.one('template', templateids: [@massed], selectTemplateGroups: %w[groupid], selectMacros: %w[macro value])
      expect(stored['templategroups'].map { |templategroup| templategroup['groupid'].to_i }).to eq([@tg1])
      expect(stored['macros'].map { |item| item['macro'] }).to eq([Live.macro(klass, 'd')])
    end

    it 'mass_remove takes the template out of the group its groups_id names' do
      expect(Live.retrying('mass_add back') { templates.mass_add(templates_id: [@massed], groups_id: [@tg2]) }).to be(true)
      expect(Live.retrying('mass_remove') { templates.mass_remove(templates_id: [@massed], groups_id: [@tg2]) }).to be(true)
      stored = Live.one('template', templateids: [@massed], selectTemplateGroups: %w[groupid])
      expect(stored['templategroups'].map { |templategroup| templategroup['groupid'].to_i }).to eq([@tg1])
    end

    it 'mass_remove refuses the singular group_id, and the template stays in the group that group_id names' do
      expect { templates.mass_remove(templates_id: [@massed], group_id: @tg1) }
        .to raise_error(ZabbixApi::ApiError, /unknown parameter group_id in call to mass_remove/)
      stored = Live.one('template', templateids: [@massed], selectTemplateGroups: %w[groupid])
      expect(stored['templategroups'].map { |templategroup| templategroup['groupid'].to_i }).to eq([@tg1])
    end

    it 'mass_remove deletes a macro given by its name, where the template.massremove reference asks for user macro IDs' do
      expect(Live.retrying('mass_add macro') { templates.mass_add(templates_id: [@massed], macros: [{ macro: Live.macro(klass, 'e'), value: 'eee' }]) }).to be(true)
      expect(Live.one('template', templateids: [@massed], selectMacros: %w[macro])['macros'].map { |item| item['macro'] }).to include(Live.macro(klass, 'e'))
      expect(Live.retrying('mass_remove macro') { templates.mass_remove(templates_id: [@massed], macros: [Live.macro(klass, 'e')]) }).to be(true)
      expect(Live.one('template', templateids: [@massed], selectMacros: %w[macro])['macros'].map { |item| item['macro'] }).not_to include(Live.macro(klass, 'e'))
    end
  end

  describe 'upserts' do
    it 'create_or_update changes a property of an existing technical name without duplicating the template' do
      expect(Live.retrying('upsert update') { templates.create_or_update(host: Live.name(klass, 'one'), description: 'via create_or_update') }).to eq(@one)
      expect(Live.one('template', templateids: [@one])['description']).to eq('via create_or_update')
      expect(Live.count('template', filter: { host: Live.name(klass, 'one') })).to eq(1)
    end

    it 'create_or_update creates when the technical name is new' do
      created = Live.owns('template', Live.retrying('upsert create') { templates.create_or_update(host: Live.name(klass, 'viacou'), groups: [{ groupid: @tg1 }]) })
      expect(Live.one('template', templateids: [created])['host']).to eq(Live.name(klass, 'viacou'))
    end

    it 'get_or_create returns the existing id and leaves one template of that name' do
      expect(Live.retrying('get_or_create found') { templates.get_or_create(host: Live.name(klass, 'viacou')) }).to eq(Live.one('template', filter: { host: Live.name(klass, 'viacou') })['templateid'].to_i)
      expect(Live.count('template', filter: { host: Live.name(klass, 'viacou') })).to eq(1)
    end

    it 'get_or_create creates when the technical name is new' do
      created = Live.owns('template', Live.retrying('get_or_create create') { templates.get_or_create(host: Live.name(klass, 'gotten'), groups: [{ groupid: @tg1 }]) })
      expect(Live.one('template', templateids: [created])['host']).to eq(Live.name(klass, 'gotten'))
    end
  end

  describe 'aliases' do
    it 'add creates the template, get reads it and destroy removes it' do
      added = Live.owns('template', Live.retrying('add') { templates.add(host: Live.name(klass, 'added'), groups: [{ groupid: @tg1 }]) })
      expect(Live.retrying('get') { templates.get(host: Live.name(klass, 'added')) }.map { |template| template['templateid'].to_i }).to eq([added])
      expect(Live.retrying('destroy') { templates.destroy(added) }).to eq(added)
      Live.disown('template', added)
      expect(Live.get('template', templateids: [added])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the template and returns its id' do
      disposable = Live.owns('template', Live.retrying('create disposable') { templates.create(host: Live.name(klass, 'disposable'), groups: [{ groupid: @tg1 }]) })
      expect(Live.retrying('delete') { templates.delete(disposable) }).to eq(disposable)
      Live.disown('template', disposable)
      expect(Live.get('template', templateids: [disposable])).to eq([])
    end
  end

  describe 'aftercare' do
    it 'leaves no template or template group under its prefix once torn down, and the standing hosts and the stock template still present' do
      Live.teardown
      expect(Live.get('template', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('templategroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('template', filter: { host: Live::TEMPLATE_NAME })['host']).to eq(Live::TEMPLATE_NAME)
    end
  end
end
