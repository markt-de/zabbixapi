# Contract: ZabbixApi::Proxygroup live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/proxygroup
#   classes:  create stores the name and the server fills in every documented default, state 0 on a
#             group just created | every documented writable property in one call | a string-keyed
#             payload reaches the server | refusals: duplicate name, missing name, read-only
#             proxy_groupid and state | both documented ranges at their bounds, one refusal each
#             with the range in the message | the seconds form and a user macro stored verbatim, an
#             Integer min_online accepted and read back as a string | reads by name, by id, the
#             whole table by membership, one get_raw representative | update writes three properties
#             at once, an unchanged and a forced update leave the object alone | the four upsert
#             branches | the writing aliases | delete removes, and is refused while a proxy belongs
#             to the group | aftercare
#   not here: the hooks and the wire shapes of the reads, which the unit spec asserts offline; bulk
#             arrays, which Basic#create and #delete handle and Basic's own spec covers; the further
#             documented get parameters (proxyids, sortfield, the common ones), one representative
#             kept; that an unchanged update sends no request, which is only observable in the
#             traffic and is asserted offline; the proxy's own surface, which is the Proxies class's
#             spec
require 'spec_helper'

RSpec.describe 'ZabbixApi::Proxygroup live', type: :acceptance do
  klass = 'proxygroup'

  before(:all) do
    # Proxies before proxy groups: a group a proxy belongs to cannot be deleted.
    Live.preclean(klass, 'proxy')
    Live.preclean(klass, 'proxygroup')
    @one = Live.owns('proxygroup', Live.retrying('create one') { Live.session.proxygroup.create(name: Live.name(klass, 'one')) })
    @bounds = Live.owns('proxygroup', Live.retrying('create bounds') { Live.session.proxygroup.create(name: Live.name(klass, 'bounds')) })
    @inuse = Live.owns('proxygroup', Live.retrying('create inuse') { Live.session.proxygroup.create(name: Live.name(klass, 'inuse')) })
    Live.owns('proxy', Live.retrying('create member') { Live.session.proxies.create(name: Live.name(klass, 'member'), operating_mode: 0, proxy_groupid: @inuse, local_address: 'proxy', local_port: '10051') })
  end

  after(:all) { Live.teardown }

  let(:proxygroup) { Live.session.proxygroup }

  describe 'create' do
    it 'stores the name and lets the server fill in every documented default' do
      stored = Live.one('proxygroup', proxy_groupids: [@one])
      expect(stored['name']).to eq(Live.name(klass, 'one'))
      expect(stored['proxy_groupid'].to_i).to eq(@one)
      expect([stored['description'], stored['failover_delay'], stored['min_online']]).to eq(['', '1m', '1'])
    end

    it 'reads back the documented state 0, unknown, on a group just created' do
      # state is the server's own: 0, unknown, until the server first updates it, then 1, offline,
      # for a group no proxy serves, whatever its failover_delay. So it is read right after the
      # create and never pinned on an older group.
      fresh = Live.owns('proxygroup', Live.retrying('create fresh') { proxygroup.create(name: Live.name(klass, 'fresh')) })
      expect(Live.one('proxygroup', proxy_groupids: [fresh])['state']).to eq('0')
    end

    it 'stores the description, failover_delay and min_online given in one call' do
      group = Live.owns('proxygroup', Live.retrying('create full') { proxygroup.create(name: Live.name(klass, 'full'), description: 'every documented field', failover_delay: '5m', min_online: '10') })
      stored = Live.one('proxygroup', proxy_groupids: [group])
      expect([stored['description'], stored['failover_delay'], stored['min_online']]).to eq(['every documented field', '5m', '10'])
    end

    it 'accepts a string-keyed payload and stores the same name' do
      group = Live.owns('proxygroup', Live.retrying('create strings') { proxygroup.create('name' => Live.name(klass, 'strings')) })
      expect(Live.one('proxygroup', proxy_groupids: [group])['name']).to eq(Live.name(klass, 'strings'))
    end

    it 'refuses a name another proxy group already carries' do
      expect { Live.retrying('duplicate name') { proxygroup.create(name: Live.name(klass, 'one')) } }.to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses a payload without the required name' do
      expect { Live.retrying('missing name') { proxygroup.create(description: 'nameless') } }.to raise_error(ZabbixApi::ApiError, /the parameter.*name.*is missing/)
    end

    # proxy_groupid is refused on create and required by update, which every update example below
    # sends.
    it 'refuses proxy_groupid, read-only on create' do
      expect { Live.retrying('read-only proxy_groupid') { proxygroup.create(name: Live.name(klass, 'gid'), proxy_groupid: 999_999) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*proxy_groupid/)
    end

    it 'refuses the read-only state' do
      expect { Live.retrying('read-only state on create') { proxygroup.create(name: Live.name(klass, 'state'), state: 3) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*state/)
    end
  end

  describe 'documented ranges' do
    it 'accepts failover_delay at both bounds and stores what was sent, the seconds form included' do
      %w[10s 15m 60s].each do |value|
        expect(Live.retrying("failover_delay #{value}") { proxygroup.update(proxy_groupid: @bounds, failover_delay: value) }).to eq(@bounds)
        expect(Live.one('proxygroup', proxy_groupids: [@bounds])['failover_delay']).to eq(value)
      end
    end

    it 'refuses a failover_delay below the bound and names the range in seconds' do
      expect { Live.retrying('failover_delay below the bound') { proxygroup.update(proxy_groupid: @bounds, failover_delay: '9s') } }.to raise_error(ZabbixApi::ApiError, /value must be one of 10-900/)
    end

    it 'accepts min_online at both bounds and stores it' do
      %w[1000 1].each do |value|
        expect(Live.retrying("min_online #{value}") { proxygroup.update(proxy_groupid: @bounds, min_online: value) }).to eq(@bounds)
        expect(Live.one('proxygroup', proxy_groupids: [@bounds])['min_online']).to eq(value)
      end
    end

    it 'refuses a min_online outside the range and names it' do
      expect { Live.retrying('min_online outside the range') { proxygroup.update(proxy_groupid: @bounds, min_online: '0') } }.to raise_error(ZabbixApi::ApiError, /value must be one of 1-1000/)
    end

    it 'accepts an Integer min_online although the proxygroup object reference types it string, and returns it as a string' do
      expect(Live.retrying('min_online integer') { proxygroup.update(proxy_groupid: @bounds, min_online: 7) }).to eq(@bounds)
      expect(Live.one('proxygroup', proxy_groupids: [@bounds])['min_online']).to eq('7')
    end

    it 'stores a user macro in failover_delay verbatim, unexpanded' do
      macro = Live.macro(klass, 'failover')
      expect(Live.retrying('failover_delay macro') { proxygroup.update(proxy_groupid: @bounds, failover_delay: macro) }).to eq(@bounds)
      expect(Live.one('proxygroup', proxy_groupids: [@bounds])['failover_delay']).to eq(macro)
    end
  end

  describe 'reads' do
    it 'get_id returns the id stored under that name' do
      expect(Live.retrying('get_id') { proxygroup.get_id(name: Live.name(klass, 'one')) }).to eq(@one)
    end

    it 'get_id returns nil for a name no proxy group carries' do
      expect(Live.retrying('get_id absent') { proxygroup.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_full_data returns the proxy group under its name with description, failover_delay, min_online and state' do
      found = Live.retrying('get_full_data') { proxygroup.get_full_data(name: Live.name(klass, 'one')) }
      expect(found.map { |group| group['proxy_groupid'].to_i }).to eq([@one])
      expect(found.first).to include('description', 'failover_delay', 'min_online', 'state')
    end

    it 'dump_by_id finds the group through the overridden key' do
      expect(Live.retrying('dump_by_id') { proxygroup.dump_by_id(proxy_groupid: @one) }.first['name']).to eq(Live.name(klass, 'one'))
    end

    it 'all maps the name to an Integer id and holds the three groups the spec set up' do
      table = Live.retrying('all') { proxygroup.all }
      expect(table[Live.name(klass, 'one')]).to eq(@one)
      expect(table.keys).to include(Live.name(klass, 'bounds'), Live.name(klass, 'inuse'))
    end

    it 'get_raw passes a documented parameter through: selectProxies in its count form' do
      row = Live.retrying('get_raw') { proxygroup.get_raw(proxy_groupids: [@inuse], selectProxies: 'count') }.first
      expect(row['proxies']).to eq('1')
    end
  end

  describe 'update' do
    it 'writes three properties in one call and all three read back' do
      group = Live.owns('proxygroup', Live.retrying('create batched') { proxygroup.create(name: Live.name(klass, 'batched')) })
      expect(Live.retrying('update') { proxygroup.update(proxy_groupid: group, description: 'batched', failover_delay: '2m', min_online: '4') }).to eq(group)
      stored = Live.one('proxygroup', proxy_groupids: [group])
      expect([stored['description'], stored['failover_delay'], stored['min_online']]).to eq(%w[batched 2m 4])
    end

    it 'renames the group and the new name reads back' do
      group = Live.owns('proxygroup', Live.retrying('create renamable') { proxygroup.create(name: Live.name(klass, 'renamable')) })
      expect(Live.retrying('rename') { proxygroup.update(proxy_groupid: group, name: Live.name(klass, 'renamed')) }).to eq(group)
      expect(Live.one('proxygroup', proxy_groupids: [group])['name']).to eq(Live.name(klass, 'renamed'))
    end

    it 'returns the id and leaves every field but state as it was when nothing differs' do
      # state is the server's verdict, not anything an update writes: a group no proxy serves moves
      # from 0 to 1 when the server first updates it, which can fall between the two reads, so the
      # comparison leaves it out.
      before_state = Live.one('proxygroup', proxy_groupids: [@one]).reject { |field, _| field == 'state' }
      expect(Live.retrying('update unchanged') { proxygroup.update(proxy_groupid: @one, name: Live.name(klass, 'one')) }).to eq(@one)
      expect(Live.one('proxygroup', proxy_groupids: [@one]).reject { |field, _| field == 'state' }).to eq(before_state)
    end

    it 'returns the id for a forced update, and the name reads back as sent' do
      expect(Live.retrying('update forced') { proxygroup.update({ proxy_groupid: @one, name: Live.name(klass, 'one') }, true) }).to eq(@one)
      expect(Live.one('proxygroup', proxy_groupids: [@one])['name']).to eq(Live.name(klass, 'one'))
    end

    it 'refuses the read-only state, and the value sent never lands' do
      expect { Live.retrying('read-only state on update') { proxygroup.update(proxy_groupid: @one, state: 3) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*state/)
      # 3 is online, which a group no proxy serves can never reach; its own state is 0, unknown, or
      # 1, offline, depending on whether the server has updated it yet, so either is accepted.
      expect(%w[0 1]).to include(Live.one('proxygroup', proxy_groupids: [@one])['state'])
    end
  end

  describe 'upserts' do
    it 'create_or_update changes a property of an existing name without duplicating the group' do
      expect(Live.retrying('upsert update') { proxygroup.create_or_update(name: Live.name(klass, 'one'), min_online: '11') }).to eq(@one)
      expect(Live.one('proxygroup', proxy_groupids: [@one])['min_online']).to eq('11')
      expect(Live.count('proxygroup', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'create_or_update creates when the name is new' do
      created = Live.owns('proxygroup', Live.retrying('upsert create') { proxygroup.create_or_update(name: Live.name(klass, 'upserted')) })
      expect(Live.one('proxygroup', proxy_groupids: [created])['name']).to eq(Live.name(klass, 'upserted'))
    end

    it 'get_or_create returns the existing id and leaves one group of that name' do
      expect(Live.retrying('get_or_create found') { proxygroup.get_or_create(name: Live.name(klass, 'one')) }).to eq(@one)
      expect(Live.count('proxygroup', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'get_or_create creates when the name is new' do
      created = Live.owns('proxygroup', Live.retrying('get_or_create create') { proxygroup.get_or_create(name: Live.name(klass, 'gotten')) })
      expect(Live.one('proxygroup', proxy_groupids: [created])['name']).to eq(Live.name(klass, 'gotten'))
    end
  end

  describe 'aliases' do
    it 'add creates the group and destroy removes it' do
      added = Live.owns('proxygroup', Live.retrying('add') { proxygroup.add(name: Live.name(klass, 'added')) })
      expect(Live.one('proxygroup', proxy_groupids: [added])['name']).to eq(Live.name(klass, 'added'))
      expect(Live.retrying('destroy') { proxygroup.destroy(added) }).to eq(added)
      Live.disown('proxygroup', added)
      expect(Live.get('proxygroup', proxy_groupids: [added])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the group and returns its id' do
      disposable = Live.owns('proxygroup', Live.retrying('create disposable') { proxygroup.create(name: Live.name(klass, 'disposable')) })
      expect(Live.retrying('delete') { proxygroup.delete(disposable) }).to eq(disposable)
      Live.disown('proxygroup', disposable)
      expect(Live.get('proxygroup', proxy_groupids: [disposable])).to eq([])
    end

    it 'refuses a group a proxy belongs to, which the proxygroup.delete reference does not document, and the group survives' do
      expect { Live.retrying('delete of an in-use group') { proxygroup.delete(@inuse) } }.to raise_error(ZabbixApi::ApiError, /is used by proxy/)
      expect(Live.one('proxygroup', proxy_groupids: [@inuse])['proxy_groupid'].to_i).to eq(@inuse)
    end
  end

  describe 'aftercare' do
    it 'leaves no proxy group or proxy under its prefix once torn down, and the standing hosts and proxy still present, the proxy in no proxy group' do
      Live.teardown
      expect(Live.get('proxygroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('proxy', search: { name: Live.prefix(klass) })).to eq([])
      standing = Live.one('proxy', filter: { name: Live::PROXY_NAME })
      expect([standing['name'], standing['proxy_groupid']]).to eq([Live::PROXY_NAME, '0'])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
    end
  end
end
