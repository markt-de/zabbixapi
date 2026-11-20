# Contract: ZabbixApi::Proxies live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/proxy
#   classes:  create stores an active proxy in no proxy group, with the documented defaults |
#             address and port default in both modes | a passive proxy keeps the address it was
#             given, and an extended read returns neither tls_psk nor tls_psk_identity | a
#             string-keyed payload reaches the server | proxy group membership and the local_address
#             it obliges | the ten timeout fields stored, one field's upper bound and its refusals |
#             hosts assigns, reassigns and clears | the reads and one documented get parameter,
#             whose nested object omits its own id | update writes, switches the operating mode,
#             leaves an equal payload alone, forces, refuses a read-only property and returns the id
#             for one that already matches | the four upsert branches and the writing aliases |
#             delete removes, is refused while a host is monitored by the proxy, and a grouped proxy
#             deletes freely | aftercare
#   not here: the hooks, and get_raw's pass-through of the further documented get parameters, which
#             the unit spec asserts offline; the TLS matrix beyond the PSK pair on a passive proxy
#             and its refusal on an active one, and the PSK length rule with it; the bounds of the
#             other nine timeout_* fields and the two further out-of-range values, one equivalence
#             class each; that an unchanged update sends no request, which no live read can show;
#             the standing proxy and the standing hosts it monitors, read by name and never written;
#             bulk arrays, which Basic#create and #delete handle and Basic's own spec covers
require 'spec_helper'

RSpec.describe 'ZabbixApi::Proxies live', type: :acceptance do
  klass = 'proxies'
  timeout_fields = [:timeout_zabbix_agent, :timeout_simple_check, :timeout_snmp_agent, :timeout_external_check, :timeout_db_monitor, :timeout_http_agent, :timeout_ssh_agent, :timeout_telnet_agent, :timeout_script, :timeout_browser]

  before(:all) do
    # Hosts before proxies, because a proxy that monitors one cannot be deleted, proxies before
    # proxy groups, and the host group last, because a host cannot be left without one.
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'proxy')
    Live.preclean(klass, 'proxygroup')
    Live.preclean(klass, 'hostgroup')

    @active = Live.owns('proxy', Live.retrying('create active') { Live.session.proxies.create(name: Live.name(klass, 'active'), operating_mode: 0) })
    @proxy_group = Live.owns('proxygroup', Live.retrying('create proxy group') { Live.session.proxygroup.create(name: Live.name(klass, 'grp')) })
    @grouped = Live.owns('proxy', Live.retrying('create grouped') { Live.session.proxies.create(name: Live.name(klass, 'grouped'), operating_mode: 0, proxy_groupid: @proxy_group, local_address: '127.0.0.1') })
    @group = Live.owns('hostgroup', Live.retrying('create host group') { Live.session.hostgroups.create(name: Live.name(klass, 'group')) })
    @host = Live.owns('host', Live.retrying('create host') { Live.session.hosts.create(host: Live.name(klass, 'host'), groups: [{ groupid: @group }]) })
    @monitoring = Live.owns('proxy', Live.retrying('create monitoring') { Live.session.proxies.create(name: Live.name(klass, 'withhost'), operating_mode: 0, hosts: [{ hostid: @host }]) })
  end

  after(:all) { Live.teardown }

  let(:proxies) { Live.session.proxies }

  describe 'create' do
    it 'stores an active proxy in no proxy group, with local_port, tls_connect, tls_accept, custom_timeouts and timeout_zabbix_agent at the defaults the proxy object reference documents' do
      stored = Live.one('proxy', proxyids: [@active])
      expect(stored['name']).to eq(Live.name(klass, 'active'))
      expect(stored['proxyid'].to_i).to eq(@active)
      expect(stored.values_at('operating_mode', 'proxy_groupid', 'local_port', 'tls_connect', 'tls_accept', 'custom_timeouts')).to eq(%w[0 0 10051 1 1 0])
      expect(stored['timeout_zabbix_agent']).to eq('')
    end

    it 'defaults address and port to 127.0.0.1:10051 in both operating modes, although the proxy object reference marks address required for a passive proxy' do
      bare = Live.owns('proxy', Live.retrying('create bare passive') { proxies.create(name: Live.name(klass, 'bare'), operating_mode: 1) })
      expect(Live.one('proxy', proxyids: [@active]).values_at('address', 'port')).to eq(['127.0.0.1', '10051'])
      expect(Live.one('proxy', proxyids: [bare]).values_at('address', 'port')).to eq(['127.0.0.1', '10051'])
    end

    it 'stores the address and port a passive proxy was given' do
      passive = Live.owns('proxy', Live.retrying('create passive') { proxies.create(name: Live.name(klass, 'passive'), operating_mode: 1, address: '10.1.2.3', port: '10061') })
      expect(Live.one('proxy', proxyids: [passive]).values_at('operating_mode', 'address', 'port')).to eq(['1', '10.1.2.3', '10061'])
    end

    it 'accepts the write-only PSK pair, stores the mode and returns neither property to an extended read' do
      psk = Live.owns('proxy', Live.retrying('create psk') { proxies.create(name: Live.name(klass, 'psk'), operating_mode: 1, address: '127.0.0.1', tls_connect: 2, tls_psk_identity: Live.name(klass, 'psk'), tls_psk: '0123456789abcdef0123456789abcdef') })
      stored = Live.one('proxy', proxyids: [psk])
      expect(stored['tls_connect']).to eq('2')
      expect(stored).not_to have_key('tls_psk')
      expect(stored).not_to have_key('tls_psk_identity')
    end

    it 'accepts a string-keyed payload and stores the same name' do
      proxy = Live.owns('proxy', Live.retrying('create strings') { proxies.create('name' => Live.name(klass, 'strings'), 'operating_mode' => 0) })
      expect(Live.one('proxy', proxyids: [proxy])['name']).to eq(Live.name(klass, 'strings'))
    end

    it 'refuses a name another proxy already carries' do
      expect { Live.retrying('duplicate name') { proxies.create(name: Live.name(klass, 'active'), operating_mode: 0) } }.to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses tls_connect PSK on an active proxy, which the proxy object reference does not document' do
      expect { Live.retrying('tls dependency') { proxies.create(name: Live.name(klass, 'psk-active'), operating_mode: 0, tls_connect: 2, tls_psk_identity: Live.name(klass, 'psk'), tls_psk: '0123456789abcdef0123456789abcdef') } }.to raise_error(ZabbixApi::ApiError, /value must be 1/)
    end
  end

  describe 'proxy group membership' do
    it 'stores the group, the local address and the default local port' do
      stored = Live.one('proxy', proxyids: [@grouped])
      expect(stored['proxy_groupid'].to_i).to eq(@proxy_group)
      expect(stored.values_at('local_address', 'local_port')).to eq(['127.0.0.1', '10051'])
    end

    it 'refuses a grouped proxy without the local_address the proxy object reference requires for one' do
      expect { Live.retrying('grouped without local_address') { proxies.create(name: Live.name(klass, 'grouped-bad'), operating_mode: 0, proxy_groupid: @proxy_group) } }.to raise_error(ZabbixApi::ApiError, /local_address/)
    end
  end

  describe 'timeouts' do
    it 'refuses custom_timeouts 1 without the timeout fields it obliges' do
      expect { Live.retrying('custom_timeouts without timeouts') { proxies.create(name: Live.name(klass, 'notimeouts'), operating_mode: 0, custom_timeouts: 1) } }.to raise_error(ZabbixApi::ApiError, /timeout_zabbix_agent.+is missing/)
    end

    it 'stores every timeout field it was given, takes the documented 600s ceiling and refuses a second above it' do
      payload = { name: Live.name(klass, 'timeouts'), operating_mode: 0, custom_timeouts: 1 }.merge(timeout_fields.to_h { |field| [field, '5s'] })
      timed = Live.owns('proxy', Live.retrying('create timeouts') { proxies.create(payload) })
      stored = Live.one('proxy', proxyids: [timed])
      expect(stored['custom_timeouts']).to eq('1')
      expect(timeout_fields.map { |field| stored[field.to_s] }.uniq).to eq(['5s'])

      expect(Live.retrying('update timeout') { proxies.update(proxyid: timed, timeout_zabbix_agent: '600s') }).to eq(timed)
      expect(Live.one('proxy', proxyids: [timed])['timeout_zabbix_agent']).to eq('600s')
      expect { Live.retrying('timeout above the ceiling') { proxies.update(proxyid: timed, timeout_zabbix_agent: '601s') } }.to raise_error(ZabbixApi::ApiError, %r{/1/timeout_zabbix_agent})
    end
  end

  describe 'hosts' do
    it 'assigns the host named on create, and the host reports the proxy back' do
      assigned = Live.get('proxy', proxyids: [@monitoring], selectHosts: %w[hostid]).first['hosts']
      expect(assigned.map { |host| host['hostid'].to_i }).to eq([@host])
      expect(Live.one('host', hostids: [@host]).values_at('monitored_by', 'proxyid')).to eq(['1', @monitoring.to_s])
    end

    it 'reassigns the host to another proxy, which leaves the first one with none' do
      expect(Live.retrying('reassign') { proxies.update(proxyid: @active, hosts: [{ hostid: @host }]) }).to eq(@active)
      expect(Live.one('host', hostids: [@host])['proxyid'].to_i).to eq(@active)
      expect(Live.get('proxy', proxyids: [@monitoring], selectHosts: 'count').first['hosts']).to eq('0')
    end

    it 'unassigns every host for an empty array, and the host falls back to the server' do
      expect(Live.retrying('unassign') { proxies.update(proxyid: @active, hosts: []) }).to eq(@active)
      expect(Live.one('host', hostids: [@host])['monitored_by']).to eq('0')
      expect(Live.get('proxy', proxyids: [@active], selectHosts: 'count').first['hosts']).to eq('0')
    end
  end

  describe 'reads' do
    it 'get_id returns the id stored under that name' do
      expect(Live.retrying('get_id') { proxies.get_id(name: Live.name(klass, 'active')) }).to eq(@active)
    end

    it 'get_id returns nil for a name no proxy carries' do
      expect(Live.retrying('get_id absent') { proxies.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_full_data returns the proxy under its name with operating_mode, custom_timeouts and lastaccess' do
      found = Live.retrying('get_full_data') { proxies.get_full_data(name: Live.name(klass, 'active')) }
      expect(found.map { |proxy| proxy['proxyid'].to_i }).to eq([@active])
      expect(found.first).to include('operating_mode', 'custom_timeouts', 'lastaccess')
    end

    it 'dump_by_id finds the proxy under its id' do
      expect(Live.retrying('dump_by_id') { proxies.dump_by_id(proxyid: @active) }.first['name']).to eq(Live.name(klass, 'active'))
    end

    it "all maps the name of this spec's proxy to its id and includes the standing proxy's name" do
      table = Live.retrying('all') { proxies.all }
      expect(table[Live.name(klass, 'active')].to_i).to eq(@active)
      expect(table).to include(Live::PROXY_NAME)
    end

    it "get_raw passes a documented parameter through: selectProxyGroup returns the group's name, failover_delay and min_online" do
      row = Live.retrying('get_raw') { proxies.get_raw(proxyids: [@grouped], selectProxyGroup: 'extend') }.first
      expect(row['proxyGroup']).to include('name' => Live.name(klass, 'grp'), 'failover_delay' => '1m', 'min_online' => '1')
    end

    # The proxy.get reference says selectProxyGroup returns "the proxy group object" and links the
    # proxy group object reference.
    it 'omits proxy_groupid from the nested object selectProxyGroup returns, which the proxy group object reference lists first' do
      row = Live.retrying('get_raw nested id') { proxies.get_raw(proxyids: [@grouped], selectProxyGroup: 'extend') }.first

      expect(row['proxyGroup'].keys).to match_array(%w[description failover_delay min_online name state])
    end
  end

  describe 'update' do
    it 'writes the description and reads it back' do
      proxy = Live.owns('proxy', Live.retrying('create describable') { proxies.create(name: Live.name(klass, 'describable'), operating_mode: 0) })
      expect(Live.retrying('update description') { proxies.update(proxyid: proxy, description: 'desc v1') }).to eq(proxy)
      expect(Live.one('proxy', proxyids: [proxy])['description']).to eq('desc v1')
    end

    it 'switches an active proxy to passive when the address comes with it' do
      proxy = Live.owns('proxy', Live.retrying('create switchable') { proxies.create(name: Live.name(klass, 'switchable'), operating_mode: 0) })
      expect(Live.retrying('update mode') { proxies.update(proxyid: proxy, operating_mode: 1, address: '10.9.9.9', port: '10062') }).to eq(proxy)
      expect(Live.one('proxy', proxyids: [proxy]).values_at('operating_mode', 'address', 'port')).to eq(['1', '10.9.9.9', '10062'])
    end

    it 'returns the id and leaves the object as it was when nothing differs, the four properties the server maintains aside' do
      # The server maintains these four read-only properties itself, so they are no evidence of what
      # an update did or did not write.
      maintained = %w[lastaccess version compatibility state]
      before_state = Live.one('proxy', proxyids: [@active]).reject { |field, _| maintained.include?(field) }
      expect(Live.retrying('update unchanged') { proxies.update(proxyid: @active, name: Live.name(klass, 'active')) }).to eq(@active)
      expect(Live.one('proxy', proxyids: [@active]).reject { |field, _| maintained.include?(field) }).to eq(before_state)
    end

    it 'returns the id for a forced update, and the name reads back as sent' do
      expect(Live.retrying('update forced') { proxies.update({ proxyid: @active, name: Live.name(klass, 'active') }, true) }).to eq(@active)
      expect(Live.one('proxy', proxyids: [@active])['name']).to eq(Live.name(klass, 'active'))
    end

    it 'refuses the read-only version property when the value differs from the stored one' do
      expect { Live.retrying('read-only version') { proxies.update(proxyid: @active, version: 987_654_321) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter/)
    end

    it 'returns the id for a read-only property whose value already matches' do
      state = Live.one('proxy', proxyids: [@active])['state']
      expect(Live.retrying('update equal read-only') { proxies.update(proxyid: @active, state: state.to_i) }).to eq(@active)
      expect(Live.one('proxy', proxyids: [@active])['state']).to eq(state)
    end
  end

  describe 'upserts and aliases' do
    it 'create_or_update changes a property of an existing name without duplicating the proxy' do
      expect(Live.retrying('upsert update') { proxies.create_or_update(name: Live.name(klass, 'active'), description: 'via cou') }).to eq(@active)
      expect(Live.one('proxy', proxyids: [@active])['description']).to eq('via cou')
      expect(Live.count('proxy', filter: { name: Live.name(klass, 'active') })).to eq(1)
    end

    it 'create_or_update creates when the name is new' do
      created = Live.owns('proxy', Live.retrying('upsert create') { proxies.create_or_update(name: Live.name(klass, 'upserted'), operating_mode: 0) })
      expect(Live.one('proxy', proxyids: [created])['name']).to eq(Live.name(klass, 'upserted'))
    end

    it 'get_or_create returns the existing id and leaves one proxy of that name' do
      expect(Live.retrying('get_or_create found') { proxies.get_or_create(name: Live.name(klass, 'active')) }).to eq(@active)
      expect(Live.count('proxy', filter: { name: Live.name(klass, 'active') })).to eq(1)
    end

    it 'get_or_create creates when the name is new' do
      created = Live.owns('proxy', Live.retrying('get_or_create create') { proxies.get_or_create(name: Live.name(klass, 'gotten'), operating_mode: 0) })
      expect(Live.one('proxy', proxyids: [created])['name']).to eq(Live.name(klass, 'gotten'))
    end

    it 'add creates the proxy and destroy removes it' do
      added = Live.owns('proxy', Live.retrying('add') { proxies.add(name: Live.name(klass, 'added'), operating_mode: 0) })
      expect(Live.one('proxy', proxyids: [added])['name']).to eq(Live.name(klass, 'added'))
      expect(Live.retrying('destroy') { proxies.destroy(added) }).to eq(added)
      Live.disown('proxy', added)
      expect(Live.get('proxy', proxyids: [added])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the proxy and returns its id' do
      disposable = Live.owns('proxy', Live.retrying('create disposable') { proxies.create(name: Live.name(klass, 'disposable'), operating_mode: 0) })
      expect(Live.retrying('delete') { proxies.delete(disposable) }).to eq(disposable)
      Live.disown('proxy', disposable)
      expect(Live.get('proxy', proxyids: [disposable])).to eq([])
    end

    it 'refuses a proxy a host is monitored by, which the proxy.delete reference does not document, and the proxy survives' do
      busy = Live.owns('proxy', Live.retrying('create busy') { proxies.create(name: Live.name(klass, 'busy'), operating_mode: 0, hosts: [{ hostid: @host }]) })
      expect { Live.retrying('delete an in-use proxy') { proxies.delete(busy) } }.to raise_error(ZabbixApi::ApiError, /is monitored by proxy/)
      expect(Live.one('proxy', proxyids: [busy])['proxyid'].to_i).to eq(busy)
      Live.retrying('release the host') { proxies.update(proxyid: busy, hosts: []) }
    end

    it 'deletes a proxy that belongs to a proxy group' do
      member = Live.owns('proxy', Live.retrying('create member') { proxies.create(name: Live.name(klass, 'member'), operating_mode: 0, proxy_groupid: @proxy_group, local_address: '127.0.0.1') })
      expect(Live.retrying('delete member') { proxies.delete(member) }).to eq(member)
      Live.disown('proxy', member)
      expect(Live.get('proxy', proxyids: [member])).to eq([])
    end
  end

  describe 'aftercare' do
    it 'leaves no proxy, proxy group, host or host group under its prefix once torn down, and the standing hosts and proxy still present, the proxied hosts still monitored by that proxy' do
      Live.teardown
      expect(Live.get('proxy', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('proxygroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])

      standing = Live.one('proxy', filter: { name: Live::PROXY_NAME })
      expect(standing['name']).to eq(Live::PROXY_NAME)
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      proxied = Live.get('host', filter: { host: Live::PROXIED_HOSTS }, output: %w[host monitored_by proxyid])
      expect(proxied.map { |host| host['host'] }).to match_array(Live::PROXIED_HOSTS)
      expect(proxied.map { |host| [host['monitored_by'], host['proxyid']] }.uniq).to eq([['1', standing['proxyid']]])
    end
  end
end
