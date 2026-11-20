# Contract: ZabbixApi facade live
#   classes:  the connection connect built: one wrapper per resource class plus server, memoised,
#             over the one client the facade exposes | three wrappers of different shapes read the
#             standing hosts and proxy and the stock host group through that client | query reaches
#             an authless and an authenticated method | a string-keyed query reaches the server like
#             a symbol-keyed one, while the server refuses an explicit nil method | logout under a
#             token leaves the connection reading | current is the connection connect made last and
#             answers what the session's own wrapper does | aftercare
#   not here: the options handed to Client, asserted offline, and the wire shape of what the facade
#             forwards - the normalised envelope of a string-keyed query, how many requests an
#             accessor costs - visible only in the traffic, which Live cannot capture, and asserted
#             offline too; the envelope, which spec/zabbixapi/client_spec.rb asserts, and the auth
#             transport, the version gate, the error types and the ending of a real login session,
#             which spec/acceptance/client_spec.rb measures; current before the first connect, a
#             refusal raised locally that needs no server; each wrapper's own live behaviour, which
#             is its own spec's subject
#
# Safety: this spec creates nothing and writes nothing. Every object it names is a standing fixture
# or the stock host group, resolved by name and only read.
require 'spec_helper'

RSpec.describe 'ZabbixApi facade live', type: :acceptance do
  klass = 'facade'

  # One accessor per resource class plus server, in the order lib/zabbixapi.rb defines them.
  accessors = {
    actions: ZabbixApi::Actions,
    configurations: ZabbixApi::Configurations,
    events: ZabbixApi::Events,
    graphs: ZabbixApi::Graphs,
    hostgroups: ZabbixApi::HostGroups,
    hosts: ZabbixApi::Hosts,
    httptests: ZabbixApi::HttpTests,
    items: ZabbixApi::Items,
    maintenance: ZabbixApi::Maintenance,
    mediatypes: ZabbixApi::Mediatypes,
    problems: ZabbixApi::Problems,
    proxies: ZabbixApi::Proxies,
    proxygroup: ZabbixApi::Proxygroup,
    roles: ZabbixApi::Roles,
    scripts: ZabbixApi::Scripts,
    server: ZabbixApi::Server,
    templategroups: ZabbixApi::TemplateGroups,
    templates: ZabbixApi::Templates,
    triggers: ZabbixApi::Triggers,
    usergroups: ZabbixApi::Usergroups,
    usermacros: ZabbixApi::Usermacros,
    users: ZabbixApi::Users,
    valuemaps: ZabbixApi::ValueMaps,
    drules: ZabbixApi::Drules
  }

  after(:all) { Live.teardown }

  # Live.session is what ZabbixApi.connect returned for this run.
  let(:zbx) { Live.session }

  describe 'the connection connect built' do
    it 'answers one wrapper per resource class plus server, and memoises every one of them' do
      built = accessors.keys.to_h { |name| [name, zbx.public_send(name)] }

      expect(built.transform_values(&:class)).to eq(accessors)
      expect(accessors.keys.reject { |name| zbx.public_send(name).equal?(built[name]) }).to eq([])
    end

    it 'exposes the client it connected with, and server reports that client version' do
      expect(zbx.client).to be_an_instance_of(ZabbixApi::Client)
      expect(zbx.server.version).to eq(zbx.client.api_version)
      expect(zbx.server.version).to match(/\A7\.\d+\.\d+\z/)
    end
  end

  describe 'the wrappers read through that client' do
    it 'hostgroups.get_id answers the id the server holds for the stock host group' do
      expect(Live.retrying('hostgroups.get_id') { zbx.hostgroups.get_id(name: Live::GROUP_NAME) })
        .to eq(Live.one('hostgroup', filter: { name: Live::GROUP_NAME })['groupid'].to_i)
    end

    it 'hosts.all carries the standing hosts, each mapped to its id as an Integer' do
      table = Live.retrying('hosts.all') { zbx.hosts.all }

      expect(table.keys).to include(*Live::AGENT_HOSTS)
      expect(table.values_at(*Live::AGENT_HOSTS)).to all(be_a(Integer))
    end

    it 'proxies.get_id answers the id the server holds for the standing proxy' do
      expect(Live.retrying('proxies.get_id') { zbx.proxies.get_id(name: Live::PROXY_NAME) })
        .to eq(Live.one('proxy', filter: { name: Live::PROXY_NAME })['proxyid'].to_i)
    end
  end

  describe 'query' do
    it 'reaches the authless apiinfo.version and answers what the version snapshot holds' do
      expect(Live.retrying('query apiinfo.version') { zbx.query(method: 'apiinfo.version', params: []) }).to eq(zbx.server.version)
    end

    it 'reaches an authenticated method and hands back the rows the server returned' do
      rows = Live.retrying('query hostgroup.get') { zbx.query(method: 'hostgroup.get', params: { output: %w[groupid name], filter: { name: Live::GROUP_NAME } }) }

      expect(rows.map { |row| row['name'] }).to eq([Live::GROUP_NAME])
    end

    it 'reaches the server for a string-keyed call too' do
      expect(Live.retrying('query string keys') { zbx.query('method' => 'apiinfo.version', 'params' => []) }).to eq(zbx.server.version)
    end

    it 'is refused for an explicit nil method as an invalid request, the server expecting a character string for /method' do
      error = nil
      expect { Live.retrying('query null method') { zbx.query(method: nil, params: []) } }
        .to raise_error(ZabbixApi::ApiError, /Invalid request\./) { |raised| error = raised }
      expect(error.error_message).to match(%r{Invalid parameter "/method": a character string is expected})
    end
  end

  describe 'logout' do
    it 'answers true under a token, the connection reading on afterwards' do
      session = Live.retrying('connect token') { ZabbixApi.connect(url: Live.url, token: Live.token) }

      expect(session.logout).to be(true)
      expect(Live.retrying('read after logout') { session.hostgroups.get_id(name: Live::GROUP_NAME) }).to be_an(Integer)
    end
  end

  describe 'ZabbixApi.current' do
    it "is the connection connect made last, and it reads what the run's own session reads" do
      previous = ZabbixApi.instance_variable_get(:@current)
      made = Live.retrying('connect') { ZabbixApi.connect(url: Live.url, token: Live.token) }

      expect(ZabbixApi.current).to be(made)
      expect(Live.retrying('read through current') { ZabbixApi.current.hostgroups.get_id(name: Live::GROUP_NAME) })
        .to eq(Live.retrying('hostgroups.get_id') { zbx.hostgroups.get_id(name: Live::GROUP_NAME) })
    ensure
      # The class-level connection outlives the example, so the example puts back what it found.
      ZabbixApi.instance_variable_set(:@current, previous)
    end
  end

  describe 'aftercare' do
    it 'leaves no host or host group under its prefix once torn down, and the standing hosts and proxy and the stock host group still present' do
      Live.teardown

      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
      expect(Live.one('hostgroup', filter: { name: Live::GROUP_NAME })['name']).to eq(Live::GROUP_NAME)
    end
  end
end
