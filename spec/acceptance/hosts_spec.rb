# Contract: ZabbixApi::Hosts live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/host,
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/hostinterface
#   classes:  the minimal create and the defaults it leaves to the server | all six extra create
#             parameters in one call | refusals: no groups, an omitted technical name, an interface
#             without dns, a conditional proxyid | an interface type outside the enum is stored, not
#             refused (pending) | a proxy-monitored host | a PSK pair stays write-only | reads by
#             name, by id, the whole table, one get_raw representative | update writes a scalar,
#             couples the visible name to a technical rename, replaces groups and interfaces, leaves
#             an unchanged object alone with and without force | read-only: a tag's automatic is
#             refused, host.update's own read-only properties are not (pending) | unlink_templates
#             unlinks without clearing, and clears under clear: true | both create_or_update
#             branches and get_or_create on an existing host | the writing aliases | delete |
#             aftercare
#   not here: the hooks, default_options and the wire shapes of the create defaults and of
#             dump_by_id, which belong to the unit spec; that an unchanged update sends no request
#             at all, which a read-back cannot tell from an issued one and the unit spec's shared
#             example group proves offline; the SNMP-details and two-main-interfaces refusals and
#             the short-PSK refusal, one representative per validator kind kept; monitored_by 2, the
#             same passthrough as monitored_by 1; flags and maintenanceid, never sent: an
#             out-of-range flags value makes a host permanently unreachable, and host.update
#             attempts to write the maintenanceid it is given, only the database's foreign-key
#             constraint refusing an unknown one; the further get parameters, server behaviour of a
#             passthrough read
require 'spec_helper'

RSpec.describe 'ZabbixApi::Hosts live', type: :acceptance do
  klass = 'hosts'

  before(:all) do
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'hostgroup')
    @group = Live.owns('hostgroup', Live.retrying('create grp1') { Live.session.hostgroups.create(name: Live.name(klass, 'grp1')) })
    @other = Live.owns('hostgroup', Live.retrying('create grp2') { Live.session.hostgroups.create(name: Live.name(klass, 'grp2')) })
    @template = Live.retrying('resolve template') { Live.session.templates.get_id(host: Live::TEMPLATE_NAME) }
    @proxy = Live.retrying('resolve proxy') { Live.session.proxies.get_id(name: Live::PROXY_NAME) }
    @host = Live.owns('host', Live.retrying('create one') { Live.session.hosts.create(host: Live.name(klass, 'one'), groups: [{ groupid: @group }]) })
    @full = Live.owns('host', Live.retrying('create full') do
      Live.session.hosts.create(host: Live.name(klass, 'full'), name: Live.name(klass, 'full-visible'),
                                description: 'spec fixture: every documented create collection',
                                groups: [{ groupid: @group }, { groupid: @other }],
                                interfaces: [{ type: 1, main: 1, useip: 1, ip: '192.0.2.11', dns: '', port: '10050' }],
                                tags: [{ tag: 'zbxapi-spec', value: klass }],
                                templates: [{ templateid: @template }],
                                macros: [{ macro: '{$ZBXAPI_SPEC_HOSTS}', value: 'hhh' }],
                                inventory_mode: 0, inventory: { location: 'Leipzig', os: 'Linux Debian' })
    end)
  end

  after(:all) { Live.teardown }

  let(:hosts) { Live.session.hosts }

  def groupids_of(hostid)
    Live.one('host', hostids: [hostid], selectHostGroups: %w[groupid])['hostgroups'].map { |entry| entry['groupid'].to_i }.sort
  end

  describe 'create' do
    it 'stores the technical name as the visible name too, and leaves seven enums at their documented defaults, the description empty, flags 0 and no interface' do
      stored = Live.one('host', hostids: [@host])
      expect(stored['host']).to eq(Live.name(klass, 'one'))
      expect(stored['name']).to eq(Live.name(klass, 'one'))
      expect(stored.values_at('status', 'description', 'flags', 'inventory_mode')).to eq(['0', '', '0', '-1'])
      expect(stored.values_at('monitored_by', 'ipmi_authtype', 'ipmi_privilege')).to eq(['0', '-1', '2'])
      expect(stored.values_at('tls_connect', 'tls_accept')).to eq(%w[1 1])
      expect(Live.one('host', hostids: [@host], selectInterfaces: %w[interfaceid])['interfaces']).to eq([])
    end

    it 'carries groups, interfaces, tags, templates, macros and inventory in one call' do
      stored = Live.one('host', hostids: [@full], selectHostGroups: %w[groupid], selectInterfaces: %w[type port],
                                selectTags: %w[tag value], selectParentTemplates: %w[templateid],
                                selectMacros: %w[macro value], selectInventory: %w[location os])
      expect(stored['name']).to eq(Live.name(klass, 'full-visible'))
      expect(stored['hostgroups'].map { |entry| entry['groupid'].to_i }.sort).to eq([@group, @other].sort)
      expect(stored['interfaces'].map { |entry| entry.values_at('type', 'port') }).to eq([%w[1 10050]])
      expect(stored['tags'].map { |entry| entry.values_at('tag', 'value') }).to eq([['zbxapi-spec', klass]])
      expect(stored['parentTemplates'].map { |entry| entry['templateid'].to_i }).to eq([@template])
      expect(stored['macros'].map { |entry| entry.values_at('macro', 'value') }).to eq([['{$ZBXAPI_SPEC_HOSTS}', 'hhh']])
      expect(stored['inventory'].values_at('location', 'os')).to eq(['Leipzig', 'Linux Debian'])
    end

    it 'refuses a host without host groups, which the host.create reference marks required' do
      expect { Live.retrying('create nogroups') { hosts.create(host: Live.name(klass, 'nogroups')) } }.to raise_error(ZabbixApi::ApiError, /cannot be empty/)
    end

    # The gem drops the unset host placeholder, so the request carries no host at all, and the
    # server answers that as it answers a null host: Wrong fields for host "".
    it 'refuses a host whose technical name the caller omitted' do
      expect { Live.retrying('create nohost') { hosts.create(groups: [{ groupid: @group }]) } }.to raise_error(ZabbixApi::ApiError, /Wrong fields for host/)
    end

    it 'refuses an interface that carries an ip but no dns, both of which the hostinterface object reference requires' do
      expect do
        Live.retrying('create noifdns') do
          hosts.create(host: Live.name(klass, 'noifdns'), groups: [{ groupid: @group }],
                       interfaces: [{ type: 1, main: 1, useip: 1, ip: '192.0.2.10', port: '10050' }])
        end
      end.to raise_error(ZabbixApi::ApiError, /Incorrect arguments passed to function/)
    end

    it 'refuses an interface type outside the four the hostinterface object reference documents' do
      pending 'type 9 is accepted on host.create and reads back as "9"'
      expect do
        Live.owns('host', Live.retrying('create badiftype') do
          hosts.create(host: Live.name(klass, 'badiftype'), groups: [{ groupid: @group }],
                       interfaces: [{ type: 9, main: 1, useip: 1, ip: '192.0.2.13', dns: '', port: '10050' }])
        end)
      end.to raise_error(ZabbixApi::ApiError, /value must be one of/)
    end

    it 'refuses monitored_by Proxy without the proxyid, which the host object reference requires for it' do
      expect { Live.retrying('create noproxy') { hosts.create(host: Live.name(klass, 'noproxy'), groups: [{ groupid: @group }], monitored_by: 1) } }
        .to raise_error(ZabbixApi::ApiError, /the parameter .*proxyid.* is missing/)
    end

    it 'stores a host monitored by the standing proxy' do
      proxied = Live.owns('host', Live.retrying('create proxied') do
        hosts.create(host: Live.name(klass, 'proxied'), groups: [{ groupid: @group }], monitored_by: 1, proxyid: @proxy)
      end)
      stored = Live.one('host', hostids: [proxied])
      expect(stored['monitored_by']).to eq('1')
      expect(stored['proxyid'].to_i).to eq(@proxy)
    end

    it 'stores a PSK pair and returns neither the key nor its identity, both of which the host object reference marks write-only' do
      psk = Live.owns('host', Live.retrying('create psk') do
        hosts.create(host: Live.name(klass, 'psk'), groups: [{ groupid: @group }], tls_connect: 2, tls_accept: 2,
                     tls_psk_identity: Live.name(klass, 'psk-identity'), tls_psk: '0123456789abcdef0123456789abcdef')
      end)
      stored = Live.one('host', hostids: [psk])
      expect(stored.values_at('tls_connect', 'tls_accept')).to eq(%w[2 2])
      expect(stored.keys & %w[tls_psk tls_psk_identity]).to eq([])
    end
  end

  describe 'reads' do
    it 'get_id returns the id stored under that technical name' do
      expect(Live.retrying('get_id') { hosts.get_id(host: Live.name(klass, 'one')) }).to eq(@host)
    end

    it 'get_id returns nil for a technical name no host carries' do
      expect(Live.retrying('get_id absent') { hosts.get_id(host: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_full_data returns the host under its technical name with flags, monitored_by and tls_connect, host groups excluded' do
      found = Live.retrying('get_full_data') { hosts.get_full_data(host: Live.name(klass, 'one')) }
      expect(found.map { |host| host['hostid'].to_i }).to eq([@host])
      expect(found.first).to include('flags', 'monitored_by', 'tls_connect')
      expect(found.first).not_to have_key('hostgroups')
    end

    it 'dump_by_id returns the host together with its host groups' do
      dumped = Live.retrying('dump_by_id') { hosts.dump_by_id(hostid: @host) }
      expect(dumped.first['host']).to eq(Live.name(klass, 'one'))
      expect(dumped.first['hostgroups'].map { |entry| entry['groupid'].to_i }).to eq([@group])
    end

    it 'all maps the technical name to an Integer id, and lists the standing hosts but not the stock template' do
      table = Live.retrying('all') { hosts.all }
      expect(table[Live.name(klass, 'one')]).to eq(@host)
      expect(table.keys).to include(*Live::AGENT_HOSTS)
      expect(table).not_to have_key(Live::TEMPLATE_NAME)
    end

    it 'get_raw passes a documented parameter through: selectParentTemplates on the templated host' do
      row = Live.retrying('get_raw') { hosts.get_raw(hostids: [@full], output: %w[hostid], selectParentTemplates: %w[templateid]) }.first
      expect(row['parentTemplates'].map { |entry| entry['templateid'].to_i }).to eq([@template])
    end
  end

  describe 'update' do
    it 'writes a scalar property and reads it back changed' do
      expect(Live.retrying('update description') { hosts.update(hostid: @host, description: 'desc v1') }).to eq(@host)
      expect(Live.one('host', hostids: [@host])['description']).to eq('desc v1')
    end

    it 'rewrites the visible name on a technical rename, unless the same request supplies one' do
      renamable = Live.owns('host', Live.retrying('create renamable') { hosts.create(host: Live.name(klass, 'renamable'), groups: [{ groupid: @group }]) })
      expect(Live.retrying('rename') { hosts.update(hostid: renamable, host: Live.name(klass, 'renamed')) }).to eq(renamable)
      expect(Live.one('host', hostids: [renamable]).values_at('host', 'name')).to eq([Live.name(klass, 'renamed')] * 2)
      expect(Live.retrying('rename keeping the visible name') { hosts.update(hostid: renamable, host: Live.name(klass, 'renamed2'), name: Live.name(klass, 'kept-visible')) }).to eq(renamable)
      expect(Live.one('host', hostids: [renamable]).values_at('host', 'name')).to eq([Live.name(klass, 'renamed2'), Live.name(klass, 'kept-visible')])
    end

    it 'replaces the group set instead of merging it, under symbol and string keys alike' do
      expect(Live.retrying('two groups') { hosts.update(hostid: @host, groups: [{ groupid: @group }, { groupid: @other }]) }).to eq(@host)
      expect(groupids_of(@host)).to eq([@group, @other].sort)
      expect(Live.retrying('one group under string keys') { hosts.update(hostid: @host, groups: [{ 'groupid' => @group }]) }).to eq(@host)
      expect(groupids_of(@host)).to eq([@group])
    end

    it 'replaces the interfaces and clears them with an empty array' do
      expect(Live.retrying('add interface') { hosts.update(hostid: @host, interfaces: [{ type: 1, main: 1, useip: 1, ip: '192.0.2.12', dns: '', port: '10050' }]) }).to eq(@host)
      expect(Live.one('host', hostids: [@host], selectInterfaces: %w[ip])['interfaces'].map { |entry| entry['ip'] }).to eq(['192.0.2.12'])
      expect(Live.retrying('clear interfaces') { hosts.update(hostid: @host, interfaces: []) }).to eq(@host)
      expect(Live.one('host', hostids: [@host], selectInterfaces: %w[ip])['interfaces']).to eq([])
    end

    it 'returns the id and leaves the object as it was when nothing differs, forced or not, the server-maintained properties aside' do
      # Read-only properties the server maintains itself: availability and maintenance state change
      # on its own schedule, so they say nothing about what this update wrote. The
      # maintenance_status example further down writes one of them deliberately and is unaffected.
      maintained = %w[active_available assigned_proxyid maintenance_status maintenance_type maintenance_from maintenanceid flags]
      before_state = Live.one('host', hostids: [@host]).reject { |field, _| maintained.include?(field) }
      expect(Live.retrying('update unchanged') { hosts.update(hostid: @host, host: Live.name(klass, 'one')) }).to eq(@host)
      expect(Live.one('host', hostids: [@host]).reject { |field, _| maintained.include?(field) }).to eq(before_state)
      expect(Live.retrying('update forced') { hosts.update({ hostid: @host, host: Live.name(klass, 'one') }, true) }).to eq(@host)
      expect(Live.one('host', hostids: [@host]).reject { |field, _| maintained.include?(field) }).to eq(before_state)
    end

    it "refuses a host tag's automatic property, which the host object reference marks read-only" do
      expect { Live.retrying('update tag automatic') { hosts.update(hostid: @host, tags: [{ tag: 'zbxapi-spec', value: klass, automatic: 1 }]) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter/)
    end

    it 'refuses the read-only maintenance_status' do
      pending 'host.update accepts and stores flags, maintenance_status, maintenance_type and maintenance_from'
      expect { Live.retrying('update maintenance_status') { hosts.update(hostid: @host, maintenance_status: 1) } }.to raise_error(ZabbixApi::ApiError, /unexpected parameter/)
    end
  end

  describe 'unlink_templates' do
    it 'unlinks the template and reports true, while its items stay on the host' do
      unlinkable = Live.owns('host', Live.retrying('create unlinkable') do
        hosts.create(host: Live.name(klass, 'unlinkable'), groups: [{ groupid: @group }], templates: [{ templateid: @template }])
      end)
      templated = Live.one('host', hostids: [unlinkable], selectItems: 'count')['items'].to_i
      expect(templated).to be_positive

      expect(Live.retrying('unlink') { hosts.unlink_templates(hosts_id: [unlinkable], templates_id: [@template]) }).to be(true)
      expect(Live.one('host', hostids: [unlinkable], selectParentTemplates: %w[templateid])['parentTemplates']).to eq([])
      expect(Live.one('host', hostids: [unlinkable], selectItems: 'count')['items'].to_i).to eq(templated)
    end

    it 'unlinks the template and reports true under clear: true, the inherited items cleared with it' do
      clearable = Live.owns('host', Live.retrying('create clearable') do
        hosts.create(host: Live.name(klass, 'clearable'), groups: [{ groupid: @group }], templates: [{ templateid: @template }])
      end)
      expect(Live.one('host', hostids: [clearable], selectItems: 'count')['items'].to_i).to be_positive

      expect(Live.retrying('unlink clear') { hosts.unlink_templates(hosts_id: [clearable], templates_id: [@template], clear: true) }).to be(true)
      expect(Live.one('host', hostids: [clearable], selectParentTemplates: %w[templateid])['parentTemplates']).to eq([])
      expect(Live.one('host', hostids: [clearable], selectItems: 'count')['items'].to_i).to eq(0)
    end
  end

  describe 'upserts and aliases' do
    it 'create_or_update writes to the host of that technical name instead of creating a second one' do
      expect(Live.retrying('upsert update') { hosts.create_or_update(host: Live.name(klass, 'one'), description: 'via upsert') }).to eq(@host)
      expect(Live.one('host', hostids: [@host])['description']).to eq('via upsert')
      expect(Live.count('host', filter: { host: Live.name(klass, 'one') })).to eq(1)
    end

    it 'create_or_update creates when the technical name is new' do
      created = Live.owns('host', Live.retrying('upsert create') { hosts.create_or_update(host: Live.name(klass, 'two'), groups: [{ groupid: @group }]) })
      expect(Live.one('host', hostids: [created])['host']).to eq(Live.name(klass, 'two'))
    end

    it 'get_or_create returns the existing id and leaves one host of that name' do
      expect(Live.retrying('get_or_create found') { hosts.get_or_create(host: Live.name(klass, 'one')) }).to eq(@host)
      expect(Live.count('host', filter: { host: Live.name(klass, 'one') })).to eq(1)
    end

    it 'add creates the host and destroy removes it' do
      added = Live.owns('host', Live.retrying('add') { hosts.add(host: Live.name(klass, 'added'), groups: [{ groupid: @group }]) })
      expect(Live.one('host', hostids: [added])['host']).to eq(Live.name(klass, 'added'))
      expect(Live.retrying('destroy') { hosts.destroy(added) }).to eq(added)
      Live.disown('host', added)
      expect(Live.get('host', hostids: [added])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the host and returns its id' do
      disposable = Live.owns('host', Live.retrying('create disposable') { hosts.create(host: Live.name(klass, 'disposable'), groups: [{ groupid: @group }]) })
      expect(Live.retrying('delete') { hosts.delete(disposable) }).to eq(disposable)
      Live.disown('host', disposable)
      expect(Live.get('host', hostids: [disposable])).to eq([])
    end
  end

  describe 'aftercare' do
    it 'leaves no host or host group under its prefix once torn down, and the standing hosts and proxy still present, the hosts without an interface' do
      Live.teardown
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      agents = Live.get('host', filter: { host: Live::AGENT_HOSTS }, selectInterfaces: %w[interfaceid])
      expect(agents.map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(agents.map { |host| host['interfaces'] }).to all(be_empty)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
