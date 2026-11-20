# Contract: ZabbixApi::TemplateGroups live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/templategroup
#   classes:  create stores the name and lets the server mint a uuid | an explicit uuid is stored
#             verbatim | a string-keyed payload reaches the server | refusals: duplicate name,
#             missing name, read-only groupid, uuid format | the documented Array form creates both
#             groups | reads by name, by id and the whole table, and the two blind-lookup guards |
#             one get_raw representative per distinct return shape, plus one narrowing flag | update
#             writes two properties at once, an unchanged and a forced update both leave the object
#             alone, a malformed uuid is refused on update as on create | the four upsert branches |
#             the writing aliases | delete removes and is refused for a template's only group |
#             aftercare
#   not here: the hook values and wire shapes, which the unit spec asserts offline; that an
#             unchanged update sends no request, visible only in the traffic and asserted offline;
#             the delete echo, a JSON type delete's Integer return hides; limitSelects, sortfield,
#             search, searchWildcardsEnabled, graphids, triggerids and the rest of the with_*
#             family, one narrowing representative kept; the mass* family and propagate, which the
#             gem does not wrap
require 'spec_helper'
require 'securerandom'

RSpec.describe 'ZabbixApi::TemplateGroups live', type: :acceptance do
  klass = 'templategroups'

  # A real UUIDv4 without its dashes: the server demands one although the templategroup object
  # reference documents no format at all.
  def uuid4
    SecureRandom.uuid.delete('-')
  end

  before(:all) do
    # Templates before groups: a group holding a template that belongs to it alone cannot be deleted.
    Live.preclean(klass, 'template')
    Live.preclean(klass, 'templategroup')
    @one = Live.owns('templategroup', Live.retrying('create one') { Live.session.templategroups.create(name: Live.name(klass, 'one')) })
    @templated = Live.owns('templategroup', Live.retrying('create templated') { Live.session.templategroups.create(name: Live.name(klass, 'templated')) })
    @template = Live.owns('template', Live.retrying('create template') { Live.session.templates.create(host: Live.name(klass, 'tpl'), groups: [{ groupid: @templated }]) })
  end

  after(:all) do
    Live.teardown
    # The bulk create registers its own ids; this sweep is a defence against an example that aborted
    # before registering.
    Live.preclean(klass, 'template')
    Live.preclean(klass, 'templategroup')
  end

  let(:templategroups) { Live.session.templategroups }

  describe 'create' do
    it 'stores the name under the id it returned, and the server fills in a uuid' do
      stored = Live.one('templategroup', groupids: [@one])
      expect(stored['name']).to eq(Live.name(klass, 'one'))
      expect(stored['groupid'].to_i).to eq(@one)
      expect(stored['uuid']).to match(/\A[0-9a-f]{32}\z/)
    end

    it 'stores a uuid the caller supplied, verbatim' do
      wanted = uuid4
      group = Live.owns('templategroup', Live.retrying('create uuid') { templategroups.create(name: Live.name(klass, 'uuid'), uuid: wanted) })
      expect(Live.one('templategroup', groupids: [group])['uuid']).to eq(wanted)
    end

    it 'accepts a string-keyed payload and the server sees the same name' do
      group = Live.owns('templategroup', Live.retrying('create strings') { templategroups.create('name' => Live.name(klass, 'strings')) })
      expect(Live.one('templategroup', groupids: [group])['name']).to eq(Live.name(klass, 'strings'))
    end

    it 'refuses a name another group already carries' do
      expect { Live.retrying('create duplicate') { templategroups.create(name: Live.name(klass, 'one')) } }
        .to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses a payload without a name' do
      expect { Live.retrying('create nameless') { templategroups.create(uuid: uuid4) } }
        .to raise_error(ZabbixApi::ApiError, /the parameter .*name.* is missing/)
    end

    it 'refuses groupid, which the templategroup object reference marks read-only' do
      expect { Live.retrying('create groupid') { templategroups.create(name: Live.name(klass, 'roid'), groupid: @one) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*groupid/)
    end

    it 'refuses 32 hex characters that are not a UUIDv4, a constraint the templategroup object reference does not document' do
      expect { Live.retrying('create baduuid') { templategroups.create(name: Live.name(klass, 'baduuid'), uuid: 'abcdef0123456789abcdef0123456789') } }
        .to raise_error(ZabbixApi::ApiError, %r{Invalid parameter .*/1/uuid.*UUIDv4 is expected})
    end

    it 'creates both groups from the documented Array form and returns their ids as Integers' do
      bulk = [{ name: Live.name(klass, 'bulk1') }, { name: Live.name(klass, 'bulk2') }]
      ids = Live.retrying('create bulk') { templategroups.create(bulk) }
      ids.each { |id| Live.owns('templategroup', id) }

      expect(ids.size).to eq(2)
      expect(ids).to all(be_a(Integer))
      stored = Live.get('templategroup', filter: { name: bulk.map { |group| group[:name] } })
      expect(stored.map { |group| group['groupid'].to_i }).to match_array(ids)
    end
  end

  describe 'reads' do
    it 'get_id returns the id stored under that name' do
      expect(Live.retrying('get_id') { templategroups.get_id(name: Live.name(klass, 'one')) }).to eq(@one)
    end

    it 'get_id returns nil for a name no group carries' do
      expect(Live.retrying('get_id absent') { templategroups.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_id refuses to run blind' do
      expect { templategroups.get_id({}) }.to raise_error(ZabbixApi::ApiError, /name not supplied/)
    end

    it 'get_full_data returns the template group under its name with uuid' do
      found = Live.retrying('get_full_data') { templategroups.get_full_data(name: Live.name(klass, 'one')) }
      expect(found.map { |group| group['groupid'].to_i }).to eq([@one])
      expect(found.first.keys).to include('uuid')
    end

    it 'dump_by_id finds the group through the overridden key' do
      expect(Live.retrying('dump_by_id') { templategroups.dump_by_id(groupid: @one) }.first['name']).to eq(Live.name(klass, 'one'))
    end

    it 'dump_by_id refuses to run blind' do
      expect { templategroups.dump_by_id({}) }.to raise_error(ZabbixApi::ApiError, /groupid not supplied/)
    end

    it 'all maps its own name to the id as an Integer and carries a stock group too' do
      table = Live.retrying('all') { templategroups.all }
      expect(table[Live.name(klass, 'one')]).to eq(@one)
      expect(table).to include('Templates')
    end
  end

  describe 'get_raw, one representative per return shape the server can answer with' do
    it "countOutput comes back as a String, counted over this spec's own groups only" do
      expect(Live.retrying('countOutput') { templategroups.get_raw(countOutput: true, groupids: [@one, @templated]) }).to eq('2')
    end

    it 'preservekeys turns the Array into a Hash keyed by the group id' do
      kept = Live.retrying('preservekeys') { templategroups.get_raw(output: ['name'], groupids: [@one], preservekeys: true) }
      expect(kept.keys).to eq([@one.to_s])
    end

    it 'selectTemplates adds the templates property as a list' do
      row = Live.retrying('selectTemplates list') { templategroups.get_raw(groupids: [@templated], selectTemplates: %w[templateid host]) }.first
      expect(row['templates'].map { |template| template['templateid'].to_i }).to eq([@template])
    end

    it 'selectTemplates in its count form answers a String count instead of a list' do
      row = Live.retrying('selectTemplates count') { templategroups.get_raw(groupids: [@templated], selectTemplates: 'count') }.first
      expect(row['templates']).to eq('1')
    end

    it 'with_templates narrows to the groups that hold a template' do
      names = Live.retrying('with_templates') { templategroups.get_raw(output: ['name'], with_templates: true) }.map { |group| group['name'] }
      expect(names).to include(Live.name(klass, 'templated'))
      expect(names).not_to include(Live.name(klass, 'one'))
    end
  end

  describe 'update' do
    it 'writes two properties in one call and both read back' do
      group = Live.owns('templategroup', Live.retrying('create renamable') { templategroups.create(name: Live.name(klass, 'renamable')) })
      wanted = uuid4
      expect(Live.retrying('update') { templategroups.update(groupid: group, name: Live.name(klass, 'renamed'), uuid: wanted) }).to eq(group)
      stored = Live.one('templategroup', groupids: [group])
      expect([stored['name'], stored['uuid']]).to eq([Live.name(klass, 'renamed'), wanted])
    end

    it 'returns the id and leaves the object exactly as it was when nothing differs' do
      before_state = Live.one('templategroup', groupids: [@one])
      expect(Live.retrying('update unchanged') { templategroups.update(groupid: @one, name: Live.name(klass, 'one')) }).to eq(@one)
      expect(Live.one('templategroup', groupids: [@one])).to eq(before_state)
    end

    it 'returns the id for a forced update, and the name reads back as sent' do
      expect(Live.retrying('update forced') { templategroups.update({ groupid: @one, name: Live.name(klass, 'one') }, true) }).to eq(@one)
      expect(Live.one('templategroup', groupids: [@one])['name']).to eq(Live.name(klass, 'one'))
    end

    it 'raises when no groupid says which group to write' do
      expect { templategroups.update(name: Live.name(klass, 'one')) }.to raise_error(ZabbixApi::ApiError, /groupid not supplied/)
    end

    it 'refuses a malformed uuid on update, and the stored one survives' do
      kept = Live.one('templategroup', groupids: [@one])['uuid']
      expect { Live.retrying('update baduuid') { templategroups.update(groupid: @one, uuid: 'abcdef0123456789abcdef0123456789') } }
        .to raise_error(ZabbixApi::ApiError, %r{Invalid parameter .*/1/uuid.*UUIDv4 is expected})
      expect(Live.one('templategroup', groupids: [@one])['uuid']).to eq(kept)
    end
  end

  describe 'upserts' do
    it 'create_or_update changes a property of an existing name without making a second group' do
      wanted = uuid4
      expect(Live.retrying('upsert update') { templategroups.create_or_update(name: Live.name(klass, 'one'), uuid: wanted) }).to eq(@one)
      expect(Live.one('templategroup', groupids: [@one])['uuid']).to eq(wanted)
      expect(Live.count('templategroup', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'create_or_update creates when the name exists nowhere' do
      created = Live.owns('templategroup', Live.retrying('upsert create') { templategroups.create_or_update(name: Live.name(klass, 'upserted')) })
      expect(Live.one('templategroup', groupids: [created])['name']).to eq(Live.name(klass, 'upserted'))
    end

    it 'get_or_create returns the existing id and leaves one group of that name' do
      expect(Live.retrying('get_or_create found') { templategroups.get_or_create(name: Live.name(klass, 'one')) }).to eq(@one)
      expect(Live.count('templategroup', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'get_or_create creates when the name exists nowhere' do
      created = Live.owns('templategroup', Live.retrying('get_or_create create') { templategroups.get_or_create(name: Live.name(klass, 'gotten')) })
      expect(Live.one('templategroup', groupids: [created])['name']).to eq(Live.name(klass, 'gotten'))
    end
  end

  describe 'aliases' do
    it 'add creates the group under the name it was given' do
      added = Live.owns('templategroup', Live.retrying('add') { templategroups.add(name: Live.name(klass, 'added')) })
      expect(Live.one('templategroup', groupids: [added])['name']).to eq(Live.name(klass, 'added'))
    end

    it 'destroy removes the group and returns its id' do
      doomed = Live.owns('templategroup', Live.retrying('create doomed') { templategroups.create(name: Live.name(klass, 'doomed')) })
      expect(Live.retrying('destroy') { templategroups.destroy(doomed) }).to eq(doomed)
      Live.disown('templategroup', doomed)
      expect(Live.get('templategroup', groupids: [doomed])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the group and returns its id' do
      disposable = Live.owns('templategroup', Live.retrying('create disposable') { templategroups.create(name: Live.name(klass, 'disposable')) })
      expect(Live.retrying('delete') { templategroups.delete(disposable) }).to eq(disposable)
      Live.disown('templategroup', disposable)
      expect(Live.get('templategroup', groupids: [disposable])).to eq([])
    end

    it "refuses a group that is a template's only group, and the group survives the refusal" do
      expect { Live.retrying('delete templated') { templategroups.delete(@templated) } }
        .to raise_error(ZabbixApi::ApiError, /cannot be without template group/)
      expect(Live.one('templategroup', groupids: [@templated])['groupid'].to_i).to eq(@templated)
    end
  end

  describe 'aftercare' do
    it 'leaves no template group or template under its prefix once torn down, and the standing hosts and proxy and the stock host group still present' do
      Live.teardown
      expect(Live.get('templategroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('template', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
      expect(Live.one('hostgroup', filter: { name: Live::GROUP_NAME })['name']).to eq(Live::GROUP_NAME)
    end
  end
end
