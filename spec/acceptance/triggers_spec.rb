# Contract: ZabbixApi::Triggers live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/trigger
#   classes:  create stores what was sent and leaves six enums, six text fields and uuid at the
#             server default | ten optional properties, tags included | one description on two hosts
#             | a string-keyed payload reaches the server | refusals: duplicate, hostid, the
#             recovery pair, an enum bound | reads: get_id scoped and unscoped, get_full_data across
#             hosts, the expanded dump against a plain read, one get_raw representative, all, a
#             trigger belonging to two hosts | update writes a batch, changes an expression in
#             place, leaves the object as it was, server-maintained state aside, when nothing
#             differs and under force, replaces tags, is refused for a read-only property | replace:
#             no-op, replacement, missing trigger | upserts: get_or_create found and created,
#             create_or_update updating in place | dependencies: stored, self refused, the master's
#             delete drops the link | a template trigger's uuid and what an inherited copy refuses |
#             delete and its refusal | aftercare
#   not here: the hooks, and the wire shapes of dump_by_id, the reads and the updates, which only
#             the traffic shows and which the unit spec asserts offline; the remaining get
#             parameters and selects, which the gem only passes through, and a pass over all six
#             priorities, one representative each; that an unchanged update sends no request, which
#             is not observable here; a server-wide trigger-event count, which triggers firing
#             anywhere on the server and the housekeeper move
require 'spec_helper'

RSpec.describe 'ZabbixApi::Triggers live', type: :acceptance do
  klass = 'triggers'
  item_key = 'zbxapi.spec.triggers.value'
  template_key = 'zbxapi.spec.triggers.tplvalue'

  before(:all) do
    # Containers only: triggers and items are contents and go with their host.
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'template')
    Live.preclean(klass, 'hostgroup')
    Live.preclean(klass, 'templategroup')

    @group = Live.owns('hostgroup', Live.retrying('hostgroup.create') { Live.session.hostgroups.create(name: Live.name(klass, 'grp')) })
    @host_names = [Live.name(klass, 'h1'), Live.name(klass, 'h2')]
    @hosts = @host_names.map do |host_name|
      hostid = Live.owns('host', Live.retrying('host.create') { Live.session.hosts.create(host: host_name, groups: [{ groupid: @group }], description: 'spec fixture: no interface, one trapper item, nothing is ever pushed to it') })
      Live.retrying('item.create') { Live.session.items.create(name: "#{host_name}-trap", key_: item_key, hostid: hostid, type: 2, value_type: 3) }
      hostid
    end
    # last() over a trapper item nothing ever writes to: these triggers cannot fire.
    @expression = @host_names.map { |host_name| "last(/#{host_name}/#{item_key})>0" }
    @base_name = Live.name(klass, 'base')
    @base = Live.retrying('trigger base') { Live.session.triggers.create(description: @base_name, expression: @expression[0]) }
    @twin = Live.retrying('trigger twin') { Live.session.triggers.create(description: @base_name, expression: @expression[1]) }
  end

  after(:all) { Live.teardown }

  let(:triggers) { Live.session.triggers }

  describe 'create' do
    it 'stores description and expression, returns the id and leaves six enums, six text fields and uuid at the server default' do
      stored = Live.one('trigger', triggerids: [@base], expandExpression: true)
      expect([stored['description'], stored['expression']]).to eq([@base_name, @expression[0]])
      expect(stored['triggerid'].to_i).to eq(@base)
      expect(stored.values_at('priority', 'status', 'type', 'recovery_mode', 'correlation_mode', 'manual_close')).to eq(%w[0 0 0 0 0 0])
      expect(stored.values_at('comments', 'opdata', 'event_name', 'url', 'recovery_expression', 'correlation_tag')).to eq(['', '', '', '', '', ''])
      expect(stored['uuid']).to eq('')
    end

    it 'stores the ten optional properties of its create, the tags among them' do
      full = Live.retrying('trigger full') do
        triggers.create(description: Live.name(klass, 'full'), expression: @expression[0], event_name: 'evt {HOST.NAME}', opdata: 'op', comments: 'a comment', priority: 5, status: 1, type: 1, url: 'http://example.invalid/', url_name: 'runbook', manual_close: 1, tags: [{ tag: 'zbxapi-spec', value: 'triggers' }])
      end
      stored = Live.one('trigger', triggerids: [full], selectTags: 'extend')
      expect(stored.values_at('event_name', 'opdata', 'comments', 'url', 'url_name')).to eq(['evt {HOST.NAME}', 'op', 'a comment', 'http://example.invalid/', 'runbook'])
      expect(stored.values_at('priority', 'status', 'type', 'manual_close')).to eq(%w[5 1 1 1])
      expect(stored['tags']).to eq([{ 'tag' => 'zbxapi-spec', 'value' => 'triggers' }])
    end

    it 'accepts the same description on a second host' do
      expect(Live.count('trigger', filter: { description: @base_name }, hostids: @hosts)).to eq(2)
      expect(Live.one('trigger', triggerids: [@twin], selectHosts: %w[hostid]).dig('hosts', 0, 'hostid').to_i).to eq(@hosts[1])
    end

    it 'accepts a string-keyed payload and stores the same description' do
      strings = Live.retrying('trigger strings') { triggers.create('description' => Live.name(klass, 'strings'), 'expression' => @expression[0]) }
      expect(Live.one('trigger', triggerids: [strings])['description']).to eq(Live.name(klass, 'strings'))
    end

    it 'refuses a second trigger with the same description and expression on one host' do
      expect { Live.retrying('create duplicate') { triggers.create(description: @base_name, expression: @expression[0]) } }.to raise_error(ZabbixApi::ApiError, /already exists on/)
    end

    it 'refuses hostid' do
      expect { Live.retrying('create hostid') { triggers.create(description: Live.name(klass, 'scoped'), expression: @expression[0], hostid: @hosts[0]) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*hostid/)
    end

    it 'refuses recovery_mode 1 without a recovery_expression and accepts it with one' do
      expect { Live.retrying('create rm1 bare') { triggers.create(description: Live.name(klass, 'rm1'), expression: @expression[0], recovery_mode: 1) } }.to raise_error(ZabbixApi::ApiError, /recovery_expression.*cannot be empty/)
      recovery = "last(/#{@host_names[0]}/#{item_key})<0"
      made = Live.retrying('trigger rm1') { triggers.create(description: Live.name(klass, 'rm1ok'), expression: @expression[0], recovery_mode: 1, recovery_expression: recovery) }
      stored = Live.one('trigger', triggerids: [made], expandExpression: true)
      expect([stored['recovery_mode'], stored['recovery_expression']]).to eq(['1', recovery])
    end

    it 'refuses a priority above the documented 0-5' do
      expect { Live.retrying('create priority 6') { triggers.create(description: Live.name(klass, 'pri'), expression: @expression[0], priority: 6) } }.to raise_error(ZabbixApi::ApiError, /value must be one of 0, 1, 2, 3, 4, 5/)
    end
  end

  describe 'reads' do
    it 'get_id scoped by hostid resolves each host separately' do
      expect(Live.retrying('get_id h1') { triggers.get_id(description: @base_name, hostid: @hosts[0]) }).to eq(@base)
      expect(Live.retrying('get_id h2') { triggers.get_id(description: @base_name, hostid: @hosts[1]) }).to eq(@twin)
    end

    it 'get_id without a hostid refuses, reporting two matches' do
      expect { Live.retrying('get_id unscoped') { triggers.get_id(description: @base_name) } }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 trigger objects, not one \(triggerid /)
    end

    it 'get_id returns nil for a description no trigger carries' do
      expect(Live.retrying('get_id absent') { triggers.get_id(description: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_full_data returns both triggers carrying the description, the first row with its expression in functionid form' do
      found = Live.retrying('get_full_data') { triggers.get_full_data(description: @base_name) }
      expect(found.map { |trigger| trigger['triggerid'].to_i }).to match_array([@base, @twin])
      expect(found.first['expression']).to match(/\A\{\d+\}/)
    end

    it 'dump_by_id returns the expression in the form the caller wrote, plus items and functions' do
      dumped = Live.retrying('dump_by_id') { triggers.dump_by_id(triggerid: @base) }.first
      expect(dumped['expression']).to eq(@expression[0])
      expect(dumped['items'].map { |item| item['key_'] }).to eq([item_key])
      expect(dumped['functions'].map { |function| function['function'] }).to eq(['last'])
    end

    it 'get_raw passes a documented parameter through: selectDependencies on a trigger without any' do
      row = Live.retrying('get_raw') { triggers.get_raw(triggerids: [@base], output: %w[triggerid], selectDependencies: 'extend') }.first
      expect(row['dependencies']).to eq([])
    end

    it 'all maps the description to an Integer id, one key for the two triggers that share it' do
      table = Live.retrying('all') { triggers.all }
      expect(table[@base_name]).to be_a(Integer)
      expect([@base, @twin]).to include(table[@base_name])
    end

    it 'a trigger whose expression spans two hosts is found under either hostid' do
      spanning = Live.retrying('trigger multi') { triggers.create(description: Live.name(klass, 'multi'), expression: "#{@expression[0]} or #{@expression[1]}") }
      expect(Live.one('trigger', triggerids: [spanning], selectHosts: %w[hostid])['hosts'].size).to eq(2)
      expect(@hosts.map { |hostid| Live.retrying('get_id multi') { triggers.get_id(description: Live.name(klass, 'multi'), hostid: hostid) } }).to eq([spanning, spanning])
    end
  end

  describe 'update' do
    it 'applies every field of a batched payload and returns the id' do
      target = Live.retrying('trigger batch') { triggers.create(description: Live.name(klass, 'batch'), expression: @expression[0]) }
      expect(Live.retrying('update batch') { triggers.update(triggerid: target, comments: 'batched', priority: 3, status: 1, opdata: 'od') }).to eq(target)
      stored = Live.one('trigger', triggerids: [target])
      expect(stored.values_at('comments', 'priority', 'status', 'opdata')).to eq(%w[batched 3 1 od])
    end

    it 'changes the expression in place, keeping the triggerid' do
      target = Live.retrying('trigger expr') { triggers.create(description: Live.name(klass, 'expr'), expression: @expression[0]) }
      changed = "last(/#{@host_names[0]}/#{item_key})>1"
      expect(Live.retrying('update expression') { triggers.update(triggerid: target, expression: changed) }).to eq(target)
      expect(Live.one('trigger', triggerids: [target], expandExpression: true)['expression']).to eq(changed)
    end

    it 'returns the id and leaves the object as it was, server-maintained state aside, when nothing differs, and under force too' do
      target = Live.retrying('trigger stable') { triggers.create(description: Live.name(klass, 'stable'), expression: @expression[0], comments: 'stable') }
      # Read-only properties the server maintains: a trigger that fires or turns unknown moves them
      # with no update having written anything.
      maintained = %w[value lastchange state error]
      before_state = Live.one('trigger', triggerids: [target]).reject { |field, _| maintained.include?(field) }
      expect(Live.retrying('update unchanged') { triggers.update(triggerid: target, comments: 'stable') }).to eq(target)
      expect(Live.one('trigger', triggerids: [target]).reject { |field, _| maintained.include?(field) }).to eq(before_state)
      expect(Live.retrying('update forced') { triggers.update({ triggerid: target, comments: 'stable' }, true) }).to eq(target)
      expect(Live.one('trigger', triggerids: [target]).reject { |field, _| maintained.include?(field) }).to eq(before_state)
    end

    it 'replaces the tags wholesale rather than merging them' do
      target = Live.retrying('trigger tags') { triggers.create(description: Live.name(klass, 'tags'), expression: @expression[0], tags: [{ tag: 'zbxapi-spec', value: 'one' }, { tag: 'zbxapi-spec', value: 'two' }]) }
      expect(Live.one('trigger', triggerids: [target], selectTags: 'extend')['tags'].size).to eq(2)
      Live.retrying('update tags') { triggers.update(triggerid: target, tags: [{ tag: 'zbxapi-spec', value: 'three' }]) }
      expect(Live.one('trigger', triggerids: [target], selectTags: 'extend')['tags']).to eq([{ 'tag' => 'zbxapi-spec', 'value' => 'three' }])
    end

    it 'refuses the read-only templateid' do
      expect { Live.retrying('update templateid') { triggers.update(triggerid: @base, templateid: 999999) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*templateid/)
    end
  end

  describe 'replace' do
    it 'keeps the trigger and its id when every supplied field already matches' do
      target = Live.retrying('trigger safe') { triggers.create(description: Live.name(klass, 'safe'), expression: @expression[0], priority: 2) }
      maintained = %w[value lastchange state error]
      before_state = Live.one('trigger', triggerids: [target]).reject { |field, _| maintained.include?(field) }
      expect(Live.retrying('replace equal') { triggers.replace(triggerid: target, description: Live.name(klass, 'safe'), expression: @expression[0], priority: 2) }).to eq(target)
      expect(Live.one('trigger', triggerids: [target]).reject { |field, _| maintained.include?(field) }).to eq(before_state)
    end

    it 'replaces the trigger with a new one when a field differs, and the old id is gone' do
      target = Live.retrying('trigger replace') { triggers.create(description: Live.name(klass, 'replace'), expression: @expression[0], priority: 2) }
      # Deliberately not wrapped in Live.retrying: replace deletes before it creates, so a
      # transient after the delete sends the retry back into the lookup, which then raises
      # "not found" rather than retrying the replacement.
      replacement = triggers.replace(triggerid: target, description: Live.name(klass, 'replaced'), expression: @expression[0], priority: 2)
      expect(replacement).not_to eq(target)
      expect(Live.get('trigger', triggerids: [target])).to eq([])
      stored = Live.one('trigger', triggerids: [replacement], expandExpression: true)
      expect([stored['description'], stored['expression'], stored['priority']]).to eq([Live.name(klass, 'replaced'), @expression[0], '2'])
    end

    it 'raises for a triggerid no trigger carries, and creates nothing' do
      expect { Live.retrying('replace absent') { triggers.replace(triggerid: 999999999, description: Live.name(klass, 'nope'), expression: @expression[0]) } }.to raise_error(ZabbixApi::ApiError, /not found, cannot replace it/)
      expect(Live.get('trigger', filter: { description: Live.name(klass, 'nope') })).to eq([])
    end
  end

  describe 'upserts' do
    it 'get_or_create with the first host returns the base trigger and creates nothing' do
      expect(Live.retrying('get_or_create found') { triggers.get_or_create(description: @base_name, expression: @expression[0], hostid: @hosts[0]) }).to eq(@base)
      expect(Live.count('trigger', filter: { description: @base_name }, hostids: @hosts)).to eq(2)
    end

    it 'get_or_create creates when the host carries no such description, and the new trigger belongs to that host' do
      made = Live.retrying('get_or_create create') { triggers.get_or_create(description: Live.name(klass, 'goc'), expression: @expression[0], hostid: @hosts[0]) }
      expect(Live.one('trigger', triggerids: [made], selectHosts: %w[hostid]).dig('hosts', 0, 'hostid').to_i).to eq(@hosts[0])
    end

    it 'create_or_update updates the existing trigger in place' do
      expect(Live.one('trigger', triggerids: [@base])['priority']).to eq('0')
      expect(Live.retrying('create_or_update') { triggers.create_or_update(description: @base_name, expression: @expression[0], hostid: @hosts[0], priority: 5) }).to eq(@base)
      expect(Live.one('trigger', triggerids: [@base])['priority']).to eq('5')

      # Restored, so the trigger is left as every other example in this file expects it, whatever
      # order RSpec runs them in - and the second call proves the update branch twice over.
      expect(Live.retrying('create_or_update restore') { triggers.create_or_update(description: @base_name, expression: @expression[0], hostid: @hosts[0], priority: 0) }).to eq(@base)
      expect(Live.one('trigger', triggerids: [@base])['priority']).to eq('0')
    end
  end

  describe 'dependencies' do
    it 'stores a dependency given on create and finds the trigger under dependent: true' do
      master = Live.retrying('trigger master') { triggers.create(description: Live.name(klass, 'master'), expression: @expression[1]) }
      dependent = Live.retrying('trigger dependent') { triggers.create(description: Live.name(klass, 'dependent'), expression: @expression[0], dependencies: [{ triggerid: master }]) }
      expect(Live.one('trigger', triggerids: [dependent], selectDependencies: 'extend').dig('dependencies', 0, 'triggerid').to_i).to eq(master)
      expect(Live.get('trigger', triggerids: [dependent], dependent: true).size).to eq(1)
    end

    it 'refuses a trigger that would depend on itself' do
      target = Live.retrying('trigger selfdep') { triggers.create(description: Live.name(klass, 'selfdep'), expression: @expression[0]) }
      expect { Live.retrying('update selfdep') { triggers.update(triggerid: target, dependencies: [{ triggerid: target }]) } }.to raise_error(ZabbixApi::ApiError, /cannot depend on the trigger/)
    end

    it 'lets the master be deleted and drops the link, leaving the dependent trigger standing' do
      master = Live.retrying('trigger master2') { triggers.create(description: Live.name(klass, 'master2'), expression: @expression[1]) }
      dependent = Live.retrying('trigger dependent2') { triggers.create(description: Live.name(klass, 'dependent2'), expression: @expression[0], dependencies: [{ triggerid: master }]) }
      expect(Live.retrying('delete master2') { triggers.delete(master) }).to eq(master)
      expect(Live.get('trigger', triggerids: [dependent], selectDependencies: 'extend').first['dependencies']).to eq([])
    end
  end

  describe 'a trigger on a template' do
    before(:all) do
      @template_group = Live.owns('templategroup', Live.retrying('templategroup.create') { Live.session.templategroups.create(name: Live.name(klass, 'tgrp')) })
      @template_name = Live.name(klass, 'tpl')
      @template = Live.owns('template', Live.retrying('template.create') { Live.session.templates.create(host: @template_name, groups: [{ groupid: @template_group }]) })
      Live.retrying('template item') { Live.session.items.create(name: "#{@template_name}-trap", key_: template_key, hostid: @template, type: 2, value_type: 3) }
      @template_trigger_name = Live.name(klass, 'tpltrig')
      @template_trigger = Live.retrying('template trigger') { Live.session.triggers.create(description: @template_trigger_name, expression: "last(/#{@template_name}/#{template_key})>0") }
      Live.retrying('link') { Live.raw('host.update', hostid: @hosts[1], templates: [{ templateid: @template }]) }
    end

    it 'gets an auto-generated uuid, where a trigger on a host carries none' do
      expect(Live.one('trigger', triggerids: [@template_trigger])['uuid']).to match(/\A[0-9a-f]{32}\z/)
      expect(Live.one('trigger', triggerids: [@base])['uuid']).to eq('')
    end

    it 'is inherited by the linked host, where the copy refuses a rename and a direct delete while its comments stay writable' do
      inherited = Live.one('trigger', hostids: [@hosts[1]], filter: { description: @template_trigger_name })
      expect(inherited['templateid'].to_i).to eq(@template_trigger)
      inherited_id = inherited['triggerid'].to_i
      expect { Live.retrying('update inherited description') { triggers.update(triggerid: inherited_id, description: Live.name(klass, 'renamed')) } }.to raise_error(ZabbixApi::ApiError, /templated trigger/)
      expect { Live.retrying('delete inherited') { triggers.delete(inherited_id) } }.to raise_error(ZabbixApi::ApiError, /templated trigger/)
      expect(Live.retrying('update inherited comments') { triggers.update(triggerid: inherited_id, comments: 'writable') }).to eq(inherited_id)
      expect(Live.one('trigger', triggerids: [inherited_id])['comments']).to eq('writable')
    end
  end

  describe 'delete' do
    it 'removes the trigger and returns its id' do
      disposable = Live.retrying('trigger disposable') { triggers.create(description: Live.name(klass, 'disposable'), expression: @expression[0]) }
      expect(Live.retrying('delete') { triggers.delete(disposable) }).to eq(disposable)
      expect(Live.get('trigger', triggerids: [disposable])).to eq([])
    end

    it 'refuses a triggerid no trigger carries' do
      expect { Live.retrying('delete absent') { triggers.delete(999999999) } }.to raise_error(ZabbixApi::ApiError, /No permissions to referred object/)
    end
  end

  describe 'aftercare' do
    it 'leaves no trigger, host, template, host group or template group under its prefix once torn down, and the standing hosts and proxy still present' do
      Live.teardown
      # Triggers and items are contents and are never swept by name; they go with their host, and
      # this read proves the triggers did.
      expect(Live.get('trigger', search: { description: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('template', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('templategroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
