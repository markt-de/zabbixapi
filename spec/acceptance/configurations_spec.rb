# Contract: ZabbixApi::Configurations live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/configuration
#   classes:  the four formats and prettyprint | the roots each options key implies, the graphs root
#             no options key names, and all of them in one file | an empty selection and an id that
#             exists nowhere | export refusals | what a template export carries | what a host export
#             leaves out and what it calls things | import: the documented no-op, createMissing
#             without children, a rule per child, updateExisting, which also removes a macro the
#             blob lacks, deleteMissing | import refusals, and the valid template a refused import
#             leaves uncreated | importcompare as a dry run | the inherited surface refused as an
#             incorrect method | aftercare
#   not here: media types, images and maps - all three are server-wide, images and maps are no
#             container the shared pre-clean can repair after a crash, and the wrapper does nothing
#             for them that templates and hosts do not already show; the hosts import rule, whose
#             createMissing and updateExisting act on hosts, and the templateLinkage rule, whose
#             createMissing and deleteMissing link and unlink templates, as the template rules here
#             act on a template and its children; an authored blob adding a low-level discovery rule
#             and a dashboard, which would test the server's uuid handling rather than the gem; the
#             five entry points that raise before any request, which send nothing for a live run to
#             observe and which the unit spec proves offline; the export permission model for Admin
#             and User type users, which would need this spec to create such a user
require 'spec_helper'
require 'json'
require 'securerandom'

RSpec.describe 'ZabbixApi::Configurations live', type: :acceptance do
  klass = 'configurations'

  tg_name = Live.name(klass, 'tg')
  hg_name = Live.name(klass, 'hg')
  t1_name = Live.name(klass, 't1')
  t2_name = Live.name(klass, 't2')
  h1_name = Live.name(klass, 'h1')
  item_name = Live.name(klass, 'item')
  trigger_name = Live.name(klass, 'trg')
  graph_name = Live.name(klass, 'graph')
  valuemap_name = Live.name(klass, 'vm')
  httptest_name = Live.name(klass, 'web')
  item_key = 'zbxapi.spec.configurations.value'
  t2_item_key = 'zbxapi.spec.configurations.inherited'
  h1_item_key = 'zbxapi.spec.configurations.own'
  description = 'spec fixture for export and import'
  plain_macro = Live.macro(klass, 'plain')
  secret_macro = Live.macro(klass, 'secret')
  secret_value = Live.name(klass, 'macro-secret')

  create_rule = { createMissing: true }
  update_rule = { updateExisting: true }
  delete_rule = { deleteMissing: true }
  compare_rules = {
    template_groups: { createMissing: true, updateExisting: true },
    templates: { createMissing: true, updateExisting: true },
    items: { createMissing: true, updateExisting: true, deleteMissing: true },
    triggers: { createMissing: true, updateExisting: true, deleteMissing: true },
    graphs: { createMissing: true, updateExisting: true, deleteMissing: true },
    valueMaps: { createMissing: true, updateExisting: true, deleteMissing: true }
  }

  # The fixture set: t1 carries an item, a trigger, a graph, a value map and two macros and is
  # linked to no host, so nothing on it is ever polled; t2 is linked to h1, which is what makes the
  # documented omission of inherited entities measurable; h1 has no interface, one item of its own
  # and one web scenario, disabled, hourly and pointed at a reserved domain, because the server
  # polls a web scenario itself.
  before(:all) do
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'template')
    Live.preclean(klass, 'hostgroup')
    Live.preclean(klass, 'templategroup')

    @tg = Live.owns('templategroup', Live.retrying('templategroup.create') { Live.session.templategroups.create(name: tg_name) })
    @hg = Live.owns('hostgroup', Live.retrying('hostgroup.create') { Live.session.hostgroups.create(name: hg_name) })
    @t1 = Live.owns('template', Live.retrying('t1.create') do
      Live.session.templates.create(host: t1_name, description: description, groups: [{ groupid: @tg }],
                                    macros: [{ macro: plain_macro, value: 'plain' }, { macro: secret_macro, type: 1, value: secret_value }])
    end)
    @item = Live.retrying('t1 item') { Live.session.items.create(name: item_name, key_: item_key, type: 7, value_type: 3, delay: '1m', hostid: @t1) }
    Live.retrying('t1 trigger') { Live.session.triggers.create(description: trigger_name, priority: 2, expression: "last(/#{t1_name}/#{item_key})>0") }
    Live.retrying('t1 graph') { Live.session.graphs.create(name: graph_name, width: 900, height: 200, gitems: [{ itemid: @item, color: '00AA00' }]) }
    Live.retrying('t1 value map') { Live.session.valuemaps.create(name: valuemap_name, hostid: @t1, mappings: [{ value: '1', newvalue: 'up' }]) }

    @t2 = Live.owns('template', Live.retrying('t2.create') { Live.session.templates.create(host: t2_name, groups: [{ groupid: @tg }]) })
    Live.retrying('t2 item') { Live.session.items.create(name: Live.name(klass, 'inherited'), key_: t2_item_key, type: 7, value_type: 3, delay: '1m', hostid: @t2) }

    @h1 = Live.owns('host', Live.retrying('h1.create') do
      Live.session.hosts.create(host: h1_name, groups: [{ groupid: @hg }], templates: [{ templateid: @t2 }],
                                description: 'spec fixture: no interface, one own item, one disabled web scenario')
    end)
    Live.retrying('h1 item') { Live.session.items.create(name: Live.name(klass, 'h1item'), key_: h1_item_key, type: 7, value_type: 3, delay: '1m', hostid: @h1) }
    Live.retrying('h1 web scenario') do
      Live.session.httptests.create(name: httptest_name, hostid: @h1, status: 1, delay: '1h',
                                    steps: [{ name: Live.name(klass, 'step'), url: 'http://example.invalid/', no: 1 }])
    end

    # The blob the imports below carry or build theirs from: this run's own export of t1, taken
    # while it is whole.
    @blob = Live::ImportGuard.export({ templates: [@t1] })
  end

  after(:all) { Live.teardown }

  let(:configurations) { Live.session.configurations }
  let(:templates) { Live.session.templates }

  # t1 is deleted and imported back below, so its id changes; every example after that resolves it
  # by name rather than trusting the one before(:all) recorded.
  def t1_id(name)
    Live.retrying('t1 lookup') { Live.session.templates.get_id(host: name) }
  end

  def roots_of(options)
    JSON.parse(Live::ImportGuard.export(options))['zabbix_export'].keys
  end

  def exported_template(id)
    JSON.parse(Live::ImportGuard.export({ templates: [id] }))['zabbix_export']['templates'].first
  end

  describe 'export' do
    it 'returns a serialized document naming the template for each of the three string formats' do
      %w[json xml yaml].each do |format|
        blob = Live::ImportGuard.export({ templates: [@t1] }, format: format)
        expect(blob).to be_a(String)
        expect(blob).to include('7.0', t1_name)
      end
    end

    it 'returns an object for format raw, where the configuration.export reference promises a string' do
      document = Live::ImportGuard.export({ templates: [@t1] }, format: 'raw')
      expect(document).to be_a(Hash)
      expect(document['zabbix_export']['templates'].map { |template| template['template'] }).to eq([t1_name])
    end

    it 'lengthens the document under prettyprint without changing what it describes' do
      plain = Live::ImportGuard.export({ templates: [@t1] })
      pretty = Live::ImportGuard.export({ templates: [@t1] }, prettyprint: true)
      expect(pretty.length).to be > plain.length
      expect(JSON.parse(pretty)).to eq(JSON.parse(plain))
    end

    it 'emits the roots its options key implies, a group alone and an object with its group' do
      expect(roots_of({ template_groups: [@tg] })).to eq(%w[version template_groups])
      expect(roots_of({ host_groups: [@hg] })).to eq(%w[version host_groups])
      expect(roots_of({ templates: [@t1] })).to include('template_groups', 'templates')
      expect(roots_of({ hosts: [@h1] })).to include('host_groups', 'hosts')
    end

    it "puts the template graph in a top-level graphs root, which no exported-element table of the manual's Configuration export/import pages lists" do
      document = JSON.parse(Live::ImportGuard.export({ templates: [@t1] }))['zabbix_export']
      expect(document.keys).to include('graphs')
      expect(document['graphs'].map { |graph| graph['name'] }).to eq([graph_name])
    end

    it "returns every element the options name in one file, as the manual's Configuration export/import page states" do
      expect(roots_of({ template_groups: [@tg], host_groups: [@hg], templates: [@t1], hosts: [@h1] }))
        .to include('template_groups', 'host_groups', 'templates', 'hosts')
    end

    it 'returns the bare version document for a selection that names nothing' do
      expect(Live.retrying('export nothing') { configurations.export(format: 'json', options: { templates: [] }) })
        .to eq('{"zabbix_export":{"version":"7.0"}}')
    end

    it 'refuses an export without format and one without options' do
      expect { Live.retrying('export without format') { configurations.export(options: { templates: [@t1] }) } }.to raise_error(ZabbixApi::ApiError, /the parameter.*format.* is missing/)
      expect { Live.retrying('export without options') { configurations.export(format: 'json') } }.to raise_error(ZabbixApi::ApiError, /the parameter.*options.* is missing/)
    end

    it 'refuses a format outside the documented four and an options key outside the documented seven' do
      expect { Live.retrying('export undocumented format') { configurations.export(format: 'csv', options: { templates: [@t1] }) } }.to raise_error(ZabbixApi::ApiError, /value must be one of/)
      expect { Live.retrying('export undocumented options key') { configurations.export(format: 'json', options: { hostgroups: [@hg] }) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*hostgroups/)
    end

    # The configuration.export reference does not say that an id that exists nowhere is accepted.
    it 'yields the bare document for an id that exists nowhere' do
      expect(roots_of(templates: [999999999])).to eq(['version'])
    end
  end

  describe 'what an export contains' do
    it 'nests the item under the template, the trigger under the item, and carries the value map and a uuid' do
      template = exported_template(@t1)
      expect(template['items'].map { |item| item['key'] }).to eq([item_key])
      expect(template['items'].first['triggers'].map { |trigger| trigger['name'] }).to eq([trigger_name])
      expect(template['valuemaps'].map { |map| map['name'] }).to eq([valuemap_name])
      expect(template['uuid']).to match(/\A[0-9a-f]{32}\z/)
    end

    it 'exports a plain macro with its value and a secret one without one, so the secret is nowhere in the blob' do
      blob = Live::ImportGuard.export({ templates: [@t1] })
      macros = JSON.parse(blob)['zabbix_export']['templates'].first['macros']
      expect(macros.find { |macro| macro['macro'] == plain_macro }['value']).to eq('plain')
      secret = macros.find { |macro| macro['macro'] == secret_macro }
      expect(secret['type']).to eq('SECRET_TEXT')
      expect(secret).not_to have_key('value')
      expect(blob).not_to include(secret_value)
    end

    it 'names the linked template of a host, keeps the host-level item, drops the inherited one and gives the host no uuid' do
      document = JSON.parse(Live::ImportGuard.export({ hosts: [@h1] }))['zabbix_export']
      host = document['hosts'].first
      expect(host['templates'].map { |template| template['name'] }).to eq([t2_name])
      expect(host['items'].map { |item| item['key'] }).to eq([h1_item_key])
      expect(JSON.generate(document)).not_to include(t2_item_key)
      expect(host).not_to have_key('uuid')
    end

    it "calls the host web-scenario root httptests, where the manual's Configuration export/import → Hosts page calls it http_tests" do
      host = JSON.parse(Live::ImportGuard.export({ hosts: [@h1] }))['zabbix_export']['hosts'].first
      expect(host.keys).to include('httptests')
      expect(host.keys).not_to include('http_tests')
      expect(host['httptests'].map { |test| test['name'] }).to eq([httptest_name])
    end
  end

  # The examples below run in the order they stand in: the template is deleted, imported back
  # without children, filled again under a rule per child, and only then updated and pruned.
  describe 'import' do
    it "accepts an empty rules object, returns true and leaves the template's templateid, host and description unchanged and its item count at one, as the configuration.import reference states for no rules" do
      before_state = Live.one('template', templateids: [@t1], output: %w[templateid host description])
      result, diff = Live::ImportGuard.import!({ format: 'json', source: @blob, rules: {} }, 'the no-op import')
      expect(result).to be(true)
      expect(diff).to eq([])
      expect(Live.one('template', templateids: [@t1], output: %w[templateid host description])).to eq(before_state)
      expect(Live.count('item', hostids: [@t1])).to eq(1)
    end

    it 'recreates the deleted template under createMissing, and alone that rule brings back neither its item nor its value map' do
      Live.retrying('delete t1') { templates.delete(@t1) }
      Live.disown('template', @t1)
      expect(Live.get('template', templateids: [@t1])).to eq([])

      Live::ImportGuard.import!({ format: 'json', source: @blob, rules: { template_groups: create_rule, templates: create_rule } }, 'templates.createMissing alone')
      restored = Live.owns('template', t1_id(t1_name))
      expect(restored).to be_a(Integer)
      expect(Live.count('item', hostids: [restored])).to eq(0)
      expect(Live.get('valuemap', hostids: [restored])).to eq([])
    end

    it 'brings each child back under a rule of its own, in one import' do
      restored = t1_id(t1_name)
      Live::ImportGuard.import!({ format: 'json', source: @blob, rules: { templates: update_rule, items: create_rule, triggers: create_rule, graphs: create_rule, valueMaps: create_rule } }, 'a rule per child')
      expect(Live.one('item', hostids: [restored])['key_']).to eq(item_key)
      expect(Live.one('trigger', hostids: [restored])['description']).to eq(trigger_name)
      expect(Live.one('graph', hostids: [restored])['name']).to eq(graph_name)
      expect(Live.get('valuemap', hostids: [restored]).map { |map| map['name'] }).to eq([valuemap_name])
    end

    it 'reverts under updateExisting a property that was changed through the API' do
      restored = t1_id(t1_name)
      Live.retrying('change the description') { templates.update(templateid: restored, description: 'changed through the API') }
      Live::ImportGuard.import!({ format: 'json', source: @blob, rules: { templates: update_rule } }, 'updateExisting')
      expect(Live.one('template', templateids: [restored], output: %w[templateid description])['description']).to eq(description)
    end

    it 'removes a macro the blob does not carry, although the configuration.import reference gives the templates rule no deleteMissing' do
      restored = t1_id(t1_name)
      extra = Live.macro(klass, 'extra')
      Live.retrying('add a macro') { Live.session.usermacros.create(hostid: restored, macro: extra, value: 'added') }
      Live::ImportGuard.import!({ format: 'json', source: @blob, rules: { templates: update_rule } }, 'updateExisting with a macro the blob lacks')

      expect(Live.get('usermacro', hostids: [restored], filter: { macro: extra })).to be_empty
    end

    it 'removes under deleteMissing the value map the blob does not carry, and keeps the one it does' do
      restored = t1_id(t1_name)
      Live.retrying('a second value map') do
        Live.session.valuemaps.create(name: Live.name(klass, 'vm2'), hostid: restored, mappings: [{ value: '9', newvalue: 'nine' }])
      end
      expect(Live.get('valuemap', hostids: [restored]).length).to eq(2)

      Live::ImportGuard.import!({ format: 'json', source: @blob, rules: { templates: update_rule, valueMaps: delete_rule } }, 'valueMaps.deleteMissing')
      expect(Live.get('valuemap', hostids: [restored]).map { |map| map['name'] }).to eq([valuemap_name])
    end

    it 'refuses an import without rules, one with an unknown rule key and one whose source is not the declared format' do
      expect { Live::ImportGuard.import!({ format: 'json', source: @blob }, 'no rules', preflight: false) }
        .to raise_error(ZabbixApi::ApiError, /the parameter.*rules.* is missing/)
      expect { Live::ImportGuard.import!({ format: 'json', source: @blob, rules: { groups: create_rule } }, 'an unknown rule key', preflight: false) }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter.*groups/)
      expect { Live::ImportGuard.import!({ format: 'xml', source: @blob, rules: { templates: create_rule } }, 'json declared as xml', preflight: false) }
        .to raise_error(ZabbixApi::ApiError, /Cannot read XML/)
    end

    it "refuses an import whose second template carries an invalid item and leaves the first uncreated, the manual's Configuration export/import page stating that import stops at the first error" do
      first = Live.name(klass, 'atomic1')
      second = Live.name(klass, 'atomic2')
      document = JSON.parse(@blob)
      document['zabbix_export'].delete('graphs')
      document['zabbix_export']['templates'] = [
        { 'uuid' => SecureRandom.uuid.delete('-'), 'template' => first, 'name' => first, 'groups' => [{ 'name' => tg_name }] },
        { 'uuid' => SecureRandom.uuid.delete('-'), 'template' => second, 'name' => second, 'groups' => [{ 'name' => tg_name }],
          'items' => [{ 'uuid' => SecureRandom.uuid.delete('-'), 'name' => second, 'key' => 'zbxapi.spec.configurations.bad', 'value_type' => 'NOPE' }] }
      ]
      blob = Live::ImportGuard.authored(JSON.generate(document), 'two templates, the second carrying an invalid item')

      expect { Live::ImportGuard.import!({ format: 'json', source: blob, rules: { templates: create_rule, items: create_rule } }, 'one invalid object', preflight: false) }
        .to raise_error(ZabbixApi::ApiError, /Invalid (tag|parameter) .*value_type/)
      expect(Live.retrying('the valid one') { templates.get_id(host: first) }).to be_nil
    end
  end

  describe 'importcompare, the dry run of import' do
    it 'reports nothing for an identical source and an object for a changed one, renaming nothing' do
      restored = t1_id(t1_name)
      expect(Live.retrying('importcompare identical') { configurations.importcompare(format: 'json', source: @blob, rules: compare_rules) }).to eq([])

      changed = Live::ImportGuard.authored(@blob.sub(item_name, Live.name(klass, 'renamed')), 'the blob with its item renamed')
      diff = Live.retrying('importcompare changed') { configurations.importcompare(format: 'json', source: changed, rules: compare_rules) }
      expect(diff).to be_a(Hash)
      expect(diff.keys).to include('templates')
      expect(Live.one('item', hostids: [restored])['name']).to eq(item_name)
    end
  end

  describe 'the inherited CRUD surface' do
    it 'reaches the server for create, delete and get, each refused as an incorrect method' do
      expect { Live.retrying('configuration.create') { configurations.create(name: Live.name(klass, 'nothing')) } }.to raise_error(ZabbixApi::ApiError, /Incorrect method.*configuration\.create/)
      expect { Live.retrying('configuration.delete') { configurations.delete(1) } }.to raise_error(ZabbixApi::ApiError, /Incorrect method.*configuration\.delete/)
      expect { Live.retrying('configuration.get') { configurations.all } }.to raise_error(ZabbixApi::ApiError, /Incorrect method.*configuration\.get/)
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
