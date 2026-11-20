# Contract: ZabbixApi::Server live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/apiinfo
#   classes:  the version is the string apiinfo.version answers on this connection, in the shape
#             the client gate demanded | a Server built straight on the connection's client agrees
#             | an independent connection agrees, so the value is the server's and not one
#             connection's | the facade hands out one memoised Server whose value never moves |
#             an apiinfo method other than version is refused, the class holding nothing else a
#             wrapper could cover | aftercare
#   not here: that Server#version equals the client's memoised api_version, which
#             spec/acceptance/client_spec.rb asserts and this file does not repeat; how many
#             requests a construction or a read costs - Live has no traffic capture, and the unit
#             spec counts them offline; the snapshot semantics, which need the client's memoised
#             value to move under an existing Server and are offline because a live client's never
#             moves; a pinned version string, because the server's version is read and never fixed;
#             that apiinfo.version also accepts an empty object, which its reference does not list
#             though the manual's API page sends one in its request example, and not a call the gem
#             makes (it sends the documented empty array, spec/zabbixapi/client_spec.rb)
#
# Safety: this spec creates nothing at all. It reads apiinfo, opens one further connection with the
# same token, and touches the standing hosts and proxy only by name in the aftercare example.
require 'spec_helper'

RSpec.describe 'ZabbixApi::Server live', type: :acceptance do
  klass = 'server'

  after(:all) { Live.teardown }

  let(:server) { Live.session.server }

  describe 'the version it reports' do
    it 'is the string apiinfo.version answers, in the shape the client gate demanded' do
      answered = Live.raw('apiinfo.version', [])

      expect(server.version).to be_a(String)
      expect(server.version).to eq(answered)
      expect(server.version).to match(/\A7\.\d+\.\d+\z/)
    end
  end

  describe 'construction' do
    it "agrees with a Server built straight on the connection's client" do
      expect(ZabbixApi::Server.new(Live.session.client).version).to eq(server.version)
    end

    it 'agrees with the Server of an independent connection' do
      other = Live.retrying('connect') { ZabbixApi.connect(url: Live.url, token: Live.token) }

      expect(other.server.version).to eq(server.version)
    end
  end

  describe 'the facade accessor' do
    it 'hands out one memoised Server, and five reads of its version agree' do
      first = Live.session.server

      expect(Live.session.server).to equal(first)
      expect(Array.new(5) { Live.session.server.version }.uniq).to eq([first.version])
    end
  end

  describe 'the apiinfo class behind it' do
    it 'refuses an apiinfo method other than version' do
      expect { Live.raw('apiinfo.details', []) }.to raise_error(ZabbixApi::ApiError, /Incorrect method .*apiinfo\.details/)
    end
  end

  describe 'aftercare' do
    it 'leaves no host or host group under its prefix once torn down, and the standing hosts and proxy still present' do
      Live.teardown

      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
