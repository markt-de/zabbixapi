# Contract: ZabbixApi::HostGroups live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/hostgroup
#   classes:  create stores the name and lets the server mint flags and a uuid | an explicit uuid is
#             stored verbatim | a string-keyed payload reaches the server | refusals: duplicate
#             name, missing name, read-only flags, uuid format | the documented Array form creates
#             every group it carries | reads by name, by id and the whole table, and the two
#             blind-lookup guards | one get_raw representative per distinct return shape, plus one
#             narrowing flag | update writes two properties at once, an unchanged and a forced
#             update both leave the object alone, no id refuses locally, flags is refused here where
#             host.update accepts it | the four upsert branches | the writing aliases | delete
#             removes and is refused for a host's only group | aftercare
#   not here: hook values and wire shapes, which the unit spec asserts offline; that an unchanged
#             update sends no request, visible only in the traffic and asserted offline; a supplied
#             groupid on create, one member kept of the read-only family that flags stands for; bulk
#             delete, which Basic#delete handles and Basic's own spec covers; sortfield, limit,
#             search, searchWildcardsEnabled, real_hosts and the rest of the with_* family, one
#             narrowing representative kept; the other six delete reasons, each needing an object
#             this spec does not own: four more the hostgroup.delete reference documents (internal
#             group, host prototype, global script, correlation condition) and two it does not (a
#             maintenance whose only group it is, an action that uses it)
require 'spec_helper'
require 'securerandom'

RSpec.describe 'ZabbixApi::HostGroups live', type: :acceptance do
  klass = 'hostgroups'

  # A real UUIDv4 without its dashes: the server demands one although the hostgroup object reference
  # documents no format at all.
  def uuid4
    SecureRandom.uuid.delete('-')
  end

  before(:all) do
    # Hosts before groups: a group that is a host's only group cannot be deleted.
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'hostgroup')
    @one = Live.owns('hostgroup', Live.retrying('create one') { Live.session.hostgroups.create(name: Live.name(klass, 'one')) })
    @hosted = Live.owns('hostgroup', Live.retrying('create hosted') { Live.session.hostgroups.create(name: Live.name(klass, 'hosted')) })
    @host = Live.owns('host', Live.retrying('create host') { Live.session.hosts.create(host: Live.name(klass, 'host'), groups: [{ groupid: @hosted }], status: 1) })
  end

  after(:all) do
    Live.teardown
    # The pre-clean catches what an example created but aborted before registering.
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'hostgroup')
  end

  let(:hostgroups) { Live.session.hostgroups }

  describe 'create' do
    it 'stores the name under the id it returned, and the server fills in flags and a uuid' do
      stored = Live.one('hostgroup', groupids: [@one])
      expect(stored['name']).to eq(Live.name(klass, 'one'))
      expect(stored['groupid'].to_i).to eq(@one)
      expect(stored['flags']).to eq('0')
      expect(stored['uuid']).to match(/\A[0-9a-f]{32}\z/)
    end

    it 'stores a uuid the caller supplied, verbatim' do
      wanted = uuid4
      group = Live.owns('hostgroup', Live.retrying('create uuid') { hostgroups.create(name: Live.name(klass, 'uuid'), uuid: wanted) })
      expect(Live.one('hostgroup', groupids: [group])['uuid']).to eq(wanted)
    end

    it 'accepts a string-keyed payload and the server sees the same name' do
      group = Live.owns('hostgroup', Live.retrying('create strings') { hostgroups.create('name' => Live.name(klass, 'strings')) })
      expect(Live.one('hostgroup', groupids: [group])['name']).to eq(Live.name(klass, 'strings'))
    end

    it 'refuses a name another group already carries' do
      expect { Live.retrying('create duplicate') { hostgroups.create(name: Live.name(klass, 'one')) } }
        .to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses a payload without a name' do
      expect { Live.retrying('create nameless') { hostgroups.create(uuid: uuid4) } }
        .to raise_error(ZabbixApi::ApiError, /the parameter .*name.* is missing/)
    end

    it 'refuses the read-only flags property' do
      expect { Live.retrying('create flags') { hostgroups.create(name: Live.name(klass, 'flags'), flags: 4) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*flags/)
    end

    it 'refuses 32 hex characters that are not a UUIDv4, a constraint the hostgroup object reference does not document' do
      expect { Live.retrying('create baduuid') { hostgroups.create(name: Live.name(klass, 'baduuid'), uuid: 'abcdef0123456789abcdef0123456789') } }
        .to raise_error(ZabbixApi::ApiError, %r{Invalid parameter .*/1/uuid.*UUIDv4 is expected})
    end

    it 'creates both groups of the documented Array form and returns their ids as Integers' do
      bulk = [{ name: Live.name(klass, 'bulk1') }, { name: Live.name(klass, 'bulk2') }]
      ids = Live.retrying('create bulk') { hostgroups.create(bulk) }
      ids.each { |id| Live.owns('hostgroup', id) }

      expect(ids.size).to eq(2)
      expect(ids).to all(be_a(Integer))
      stored = Live.get('hostgroup', filter: { name: bulk.map { |group| group[:name] } })
      expect(stored.map { |group| group['groupid'].to_i }).to match_array(ids)
    end
  end

  describe 'reads' do
    it 'get_id returns the id stored under that name' do
      expect(Live.retrying('get_id') { hostgroups.get_id(name: Live.name(klass, 'one')) }).to eq(@one)
    end

    it 'get_id returns nil for a name no group carries' do
      expect(Live.retrying('get_id absent') { hostgroups.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_id refuses to run blind' do
      expect { hostgroups.get_id({}) }.to raise_error(ZabbixApi::ApiError, /name not supplied/)
    end

    it 'get_full_data returns the host group under its name with uuid and flags' do
      found = Live.retrying('get_full_data') { hostgroups.get_full_data(name: Live.name(klass, 'one')) }
      expect(found.map { |group| group['groupid'].to_i }).to eq([@one])
      expect(found.first.keys).to include('uuid', 'flags')
    end

    it 'dump_by_id finds the group through the overridden key' do
      expect(Live.retrying('dump_by_id') { hostgroups.dump_by_id(groupid: @one) }.first['name']).to eq(Live.name(klass, 'one'))
    end

    it 'dump_by_id refuses to run blind' do
      expect { hostgroups.dump_by_id({}) }.to raise_error(ZabbixApi::ApiError, /groupid not supplied/)
    end

    it 'all maps its own name to the id as an Integer and carries the stock host group too' do
      table = Live.retrying('all') { hostgroups.all }
      expect(table[Live.name(klass, 'one')]).to eq(@one)
      expect(table).to include(Live::GROUP_NAME)
    end
  end

  describe 'get_raw, one representative per return shape the server can answer with' do
    it "countOutput comes back as a String, counted over this spec's own groups only" do
      expect(Live.retrying('countOutput') { hostgroups.get_raw(countOutput: true, groupids: [@one, @hosted]) }).to eq('2')
    end

    it 'preservekeys turns the Array into a Hash keyed by the group id' do
      kept = Live.retrying('preservekeys') { hostgroups.get_raw(output: ['name'], groupids: [@one], preservekeys: true) }
      expect(kept.keys).to eq([@one.to_s])
    end

    it 'selectHosts adds the hosts property as a list' do
      row = Live.retrying('selectHosts list') { hostgroups.get_raw(groupids: [@hosted], selectHosts: %w[hostid host]) }.first
      expect(row['hosts'].map { |host| host['hostid'].to_i }).to eq([@host])
    end

    it 'selectHosts in its count form answers a String count instead of a list' do
      row = Live.retrying('selectHosts count') { hostgroups.get_raw(groupids: [@hosted], selectHosts: 'count') }.first
      expect(row['hosts']).to eq('1')
    end

    it 'with_hosts narrows to the groups that hold a host' do
      names = Live.retrying('with_hosts') { hostgroups.get_raw(output: ['name'], with_hosts: true) }.map { |group| group['name'] }
      expect(names).to include(Live.name(klass, 'hosted'))
      expect(names).not_to include(Live.name(klass, 'one'))
    end
  end

  describe 'update' do
    it 'writes two properties in one call and both read back' do
      group = Live.owns('hostgroup', Live.retrying('create renamable') { hostgroups.create(name: Live.name(klass, 'renamable')) })
      wanted = uuid4
      expect(Live.retrying('update') { hostgroups.update(groupid: group, name: Live.name(klass, 'renamed'), uuid: wanted) }).to eq(group)
      stored = Live.one('hostgroup', groupids: [group])
      expect([stored['name'], stored['uuid']]).to eq([Live.name(klass, 'renamed'), wanted])
    end

    it 'returns the id and leaves the object exactly as it was when nothing differs' do
      before_state = Live.one('hostgroup', groupids: [@one])
      expect(Live.retrying('update unchanged') { hostgroups.update(groupid: @one, name: Live.name(klass, 'one')) }).to eq(@one)
      expect(Live.one('hostgroup', groupids: [@one])).to eq(before_state)
    end

    it 'returns the id for a forced update, and the name reads back as sent' do
      expect(Live.retrying('update forced') { hostgroups.update({ groupid: @one, name: Live.name(klass, 'one') }, true) }).to eq(@one)
      expect(Live.one('hostgroup', groupids: [@one])['name']).to eq(Live.name(klass, 'one'))
    end

    it 'raises when no groupid says which group to write' do
      expect { hostgroups.update(name: Live.name(klass, 'one')) }.to raise_error(ZabbixApi::ApiError, /groupid not supplied/)
    end

    it 'refuses the read-only flags property and leaves the stored value at 0' do
      expect { Live.retrying('update flags') { hostgroups.update(groupid: @one, flags: 4) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*flags/)
      expect(Live.one('hostgroup', groupids: [@one])['flags']).to eq('0')
    end
  end

  describe 'upserts' do
    it 'create_or_update changes a property of an existing name without making a second group' do
      wanted = uuid4
      expect(Live.retrying('upsert update') { hostgroups.create_or_update(name: Live.name(klass, 'one'), uuid: wanted) }).to eq(@one)
      expect(Live.one('hostgroup', groupids: [@one])['uuid']).to eq(wanted)
      expect(Live.count('hostgroup', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'create_or_update creates when the name exists nowhere' do
      created = Live.owns('hostgroup', Live.retrying('upsert create') { hostgroups.create_or_update(name: Live.name(klass, 'upserted')) })
      expect(Live.one('hostgroup', groupids: [created])['name']).to eq(Live.name(klass, 'upserted'))
    end

    it 'get_or_create returns the existing id and leaves one group of that name' do
      expect(Live.retrying('get_or_create found') { hostgroups.get_or_create(name: Live.name(klass, 'one')) }).to eq(@one)
      expect(Live.count('hostgroup', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'get_or_create creates when the name exists nowhere' do
      created = Live.owns('hostgroup', Live.retrying('get_or_create create') { hostgroups.get_or_create(name: Live.name(klass, 'gotten')) })
      expect(Live.one('hostgroup', groupids: [created])['name']).to eq(Live.name(klass, 'gotten'))
    end
  end

  describe 'aliases' do
    it 'add creates the group under the name it was given' do
      added = Live.owns('hostgroup', Live.retrying('add') { hostgroups.add(name: Live.name(klass, 'added')) })
      expect(Live.one('hostgroup', groupids: [added])['name']).to eq(Live.name(klass, 'added'))
    end

    it 'destroy removes the group and returns its id' do
      doomed = Live.owns('hostgroup', Live.retrying('create doomed') { hostgroups.create(name: Live.name(klass, 'doomed')) })
      expect(Live.retrying('destroy') { hostgroups.destroy(doomed) }).to eq(doomed)
      Live.disown('hostgroup', doomed)
      expect(Live.get('hostgroup', groupids: [doomed])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the group and returns its id' do
      disposable = Live.owns('hostgroup', Live.retrying('create disposable') { hostgroups.create(name: Live.name(klass, 'disposable')) })
      expect(Live.retrying('delete') { hostgroups.delete(disposable) }).to eq(disposable)
      Live.disown('hostgroup', disposable)
      expect(Live.get('hostgroup', groupids: [disposable])).to eq([])
    end

    it "refuses a group that is a host's only group, and the group survives the refusal" do
      expect { Live.retrying('delete hosted') { hostgroups.delete(@hosted) } }
        .to raise_error(ZabbixApi::ApiError, /cannot be without host group/)
      expect(Live.one('hostgroup', groupids: [@hosted])['groupid'].to_i).to eq(@hosted)
    end
  end

  describe 'aftercare' do
    it 'leaves no host group or host under its prefix once torn down, and the standing hosts and proxy and the stock host group still present' do
      Live.teardown
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
      expect(Live.one('hostgroup', filter: { name: Live::GROUP_NAME })['name']).to eq(Live::GROUP_NAME)
    end
  end
end
