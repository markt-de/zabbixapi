# Contract: ZabbixApi, the facade
#   classes:  connect builds one Client out of the options and registers the connection | new builds
#             one and registers nothing | current raises before the first connect and tracks the
#             newest one afterwards | 24 accessors, one per resource class plus server, each its own
#             class, each memoised, and no accessor beyond them | building a wrapper leaves the
#             client untouched, server excepted, which reads the client's version once | a wrapper's
#             call reaches the facade's own client in the shape Client takes | query forwards method
#             and params and returns the answer | query normalises its envelope keys, so a
#             string-keyed call sends the same request | query leaves the params value as the caller
#             built it | logout delegates and answers what the client answered
#   not here: what the Client does with the options it was handed - the envelope, the auth
#             transport, the version gate, the errors, the redaction - which
#             zabbixapi/client_spec.rb asserts; Server's snapshot semantics (classes/server_spec.rb)
#             and every wrapper's own behaviour (each class's own spec); connecting for real, which
#             spec/acceptance/zabbixapi_spec.rb does - no example here opens a socket
require 'spec_helper'

RSpec.describe ZabbixApi do
  url = 'http://zabbix.example.invalid/api_jsonrpc.php'
  token = 'spec-facade-token-4a7b'
  version = '7.0.30'

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

  # No socket: Client is a verifying double, so what the facade hands it is checked against the
  # real Client interface, and both the options it was built with and the bodies it was sent are
  # captured in the shape Client receives them - before any JSON, which is Client's own business.
  let(:built_with) { [] }
  let(:sent) { [] }
  let(:answer) { [] }
  let(:client) { instance_double(ZabbixApi::Client, api_version: version, options: { debug: false }) }
  let(:zbx) { described_class.new(url: url, token: token) }

  before do
    allow(ZabbixApi::Client).to receive(:new) do |options|
      built_with << options
      client
    end
    allow(client).to receive(:api_request) do |body|
      sent << body
      answer
    end
    allow(client).to receive(:logout).and_return(true)
  end

  # connect and the examples that clear the current connection write a class-level variable that
  # outlives the example, so the file puts back whatever it found there.
  around do |example|
    previous = ZabbixApi.instance_variable_get(:@current)
    example.run
  ensure
    ZabbixApi.instance_variable_set(:@current, previous)
  end

  describe '.connect' do
    it 'builds one client out of the options it was given and exposes it' do
      connection = described_class.connect(url: url, token: token)

      expect(built_with).to eq([{ url: url, token: token }])
      expect(connection).to be_an_instance_of(described_class)
      expect(connection.client).to be(client)
    end

    it 'registers the connection it built as the current one' do
      connection = described_class.connect(url: url, token: token)

      expect(described_class.current).to be(connection)
    end

    it 'builds a second connection on the next connect and gives it the current slot' do
      first = described_class.connect(url: url, token: token)
      second = described_class.connect(url: url, token: token)

      expect(first).not_to be(second)
      expect(built_with.length).to eq(2)
      expect(described_class.current).to be(second)
    end
  end

  describe '.new' do
    it 'builds a connection and registers none' do
      ZabbixApi.instance_variable_set(:@current, nil)
      built = described_class.new(url: url, token: token)

      expect(built.client).to be(client)
      expect(ZabbixApi.instance_variable_get(:@current)).to be_nil
    end
  end

  describe '.current' do
    it 'raises an ApiError naming connect before any connection exists, and builds no client doing it' do
      ZabbixApi.instance_variable_set(:@current, nil)

      expect { described_class.current }.to raise_error(ZabbixApi::ApiError, /no current connection: call ZabbixApi\.connect first/)
      expect(built_with).to be_empty
    end
  end

  describe 'the resource accessors' do
    accessors.each do |name, klass|
      it "#{name} answers its own #{klass.name.split('::').last} wrapper and memoises it" do
        first = zbx.public_send(name)

        expect(first).to be_an_instance_of(klass)
        expect(zbx.public_send(name)).to be(first)
      end
    end

    it 'carries those accessors and nothing else, client, query and logout being the rest of the surface' do
      expect(described_class.public_instance_methods(false).sort).to eq((accessors.keys + [:client, :logout, :query]).sort)
    end

    it 'builds every wrapper but server without touching the client' do
      accessors.each_key { |name| zbx.public_send(name) unless name == :server }

      expect(sent).to be_empty
      expect(client).not_to have_received(:api_version)
    end

    it "runs a wrapper's call on the facade's own client, in the shape Client takes" do
      allow(client).to receive(:api_request) do |body|
        sent << body
        [{ 'groupid' => '4', 'name' => 'Zabbix servers' }]
      end

      expect(zbx.hostgroups.get_id(name: 'Zabbix servers')).to eq(4)
      expect(sent).to eq([{ method: 'hostgroup.get', params: { filter: { name: 'Zabbix servers' }, output: %w[groupid name] } }])
    end
  end

  describe '#server' do
    it 'takes its version from the client as it is built, and the memo keeps that at one read' do
      expect(zbx.server.version).to eq(version)

      zbx.server
      expect(client).to have_received(:api_version).once
    end
  end

  describe '#query' do
    let(:answer) { version }

    it 'hands the method and the params to the client untouched and returns what it answered' do
      expect(zbx.query(method: 'apiinfo.version', params: [])).to eq(version)
      expect(sent).to eq([{ method: 'apiinfo.version', params: [] }])
    end

    it 'normalises its envelope keys, so a string-keyed call sends what the symbol-keyed one sends' do
      zbx.query('method' => 'apiinfo.version', 'params' => [])

      expect(sent).to eq([{ method: 'apiinfo.version', params: [] }])
    end

    it "leaves the params value alone, the caller's own payload reaching the client as it was built" do
      zbx.query(method: 'host.get', params: { 'output' => %w[hostid] })

      expect(sent).to eq([{ method: 'host.get', params: { 'output' => %w[hostid] } }])
    end
  end

  describe '#logout' do
    it 'delegates to the client and answers what the client answered' do
      expect(zbx.logout).to be(true)

      expect(client).to have_received(:logout).once
      expect(sent).to be_empty
    end
  end
end
