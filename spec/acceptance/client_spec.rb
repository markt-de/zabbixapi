# Contract: ZabbixApi::Client live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/apiinfo,
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/user
#   classes:  the token connect and the version the gate accepts | the Bearer token authenticates an
#             ordinary read | an authless method goes through, which only a missing header allows |
#             user.login and its session, logout ending it | logout under a token returns true and
#             the token keeps working | basic auth: the token travels in the body and is accepted |
#             errors: an API refusal, a wrong path, a dead port, a refused login with the password
#             masked, a passphrase a refusal quotes back masked | no_proxy | aftercare
#   not here: the envelope, the header shapes and the memoisation of api_version - this spec
#             captures no traffic, so how many requests a call made and what they carried is
#             asserted offline; ignore_version, verify_ssl, HTTP basic-auth enforcement and a
#             working proxy, which need a server that is not a 7.x release, an HTTPS endpoint, a web
#             server demanding basic credentials and an HTTP proxy, none of which the suite
#             requires; the timeout option beyond the bound this file uses to keep the dead-port
#             example short
#
# Safety: this spec creates no object: its one create, a disabled discovery rule on an RFC 5737
# address, is refused for an over-long SNMPv3 passphrase, and is registered for teardown should the
# server accept it. The stock Admin account and its default password are hardcoded for the two
# examples that log in, because a token can reach neither user.login nor a session logout. The
# refused login uses a nonexistent username, so that no existing account approaches a login lockout.
require 'spec_helper'

RSpec.describe 'ZabbixApi::Client live', type: :acceptance do
  klass = 'client'

  before(:all) { Live.preclean(klass, 'drule') }
  after(:all) { Live.teardown }

  describe 'connecting with a token' do
    it 'reports the running version, which is what the client gate demands' do
      version = Live.retrying('api_version') { Live.session.client.api_version }

      expect(version).to match(/\A7\.\d+\.\d+\z/)
      expect(Live.session.server.version).to eq(version)
    end

    it 'authenticates an ordinary read with the token' do
      groups = Live.retrying('hostgroup.get') { Live.session.query(method: 'hostgroup.get', params: { output: %w[groupid name], filter: { name: Live::GROUP_NAME } }) }

      expect(groups.map { |group| group['name'] }).to eq([Live::GROUP_NAME])
    end

    it 'reaches user.checkAuthentication, whose answer carries userid, username and type and no sessionid' do
      owner = Live.retrying('checkAuthentication') { Live.session.query(method: 'user.checkAuthentication', params: { token: Live.token }) }

      expect(owner).to include('userid', 'username', 'type')
      expect(owner).not_to include('sessionid')
    end

    it 'connects with the proxy handling switched off' do
      session = Live.retrying('connect no_proxy') { ZabbixApi.connect(url: Live.url, token: Live.token, no_proxy: true) }

      expect(session.client.api_version).to match(/\A7\.\d+\.\d+\z/)
    end
  end

  describe 'connecting with a username and a password' do
    it 'logs in, authenticates a read with the session it got, and logs out again' do
      session = Live.retrying('connect login') { ZabbixApi.connect(url: Live.url, user: 'Admin', password: 'zabbix') }

      expect(session.client.api_version).to match(/\A7\.\d+\.\d+\z/)
      expect(Live.retrying('read on session') { session.query(method: 'hostgroup.get', params: { countOutput: true, filter: { name: Live::GROUP_NAME } }) }).to eq('1')
      expect(Live.retrying('logout') { session.logout }).to be(true)
    end

    it 'ends the session on logout, and the session token stops working' do
      session = Live.retrying('connect login') { ZabbixApi.connect(url: Live.url, user: 'Admin', password: 'zabbix') }

      expect(Live.retrying('logout') { session.logout }).to be(true)
      expect { Live.retrying('read on ended session') { session.query(method: 'hostgroup.get', params: { countOutput: true, filter: { name: Live::GROUP_NAME } }) } }.to raise_error(ZabbixApi::ApiError, /re-login/)
    end

    it 'refuses a login under a nonexistent username, masking the password rather than quoting it back' do
      error = nil
      expect { Live.retrying('connect wrong password') { ZabbixApi.connect(url: Live.url, user: Live.name(klass, 'nosuchuser'), password: 'wrong-Pw-9c1f') } }
        .to raise_error(ZabbixApi::ApiError, /Incorrect user name or password/) { |raised| error = raised }
      expect(error.message).to match(/"password": "\*\*\*"/)
      expect(error.message).not_to include('wrong-Pw-9c1f')
    end
  end

  describe 'logout under token auth' do
    it 'returns true and leaves the token working' do
      session = Live.retrying('connect token') { ZabbixApi.connect(url: Live.url, token: Live.token) }

      expect(session.logout).to be(true)
      expect(Live.retrying('read after logout') { session.query(method: 'hostgroup.get', params: { countOutput: true, filter: { name: Live::GROUP_NAME } }) }).to eq('1')
    end
  end

  describe 'HTTP basic auth' do
    it 'authenticates a read while basic auth occupies the Authorization header' do
      session = Live.retrying('connect basic') { ZabbixApi.connect(url: Live.url, token: Live.token, http_user: 'Admin', http_password: 'zabbix') }

      expect(session.client.basic_auth?).to be(true)
      expect(Live.retrying('read under basic auth') { session.query(method: 'hostgroup.get', params: { countOutput: true, filter: { name: Live::GROUP_NAME } }) }).to eq('1')
    end
  end

  describe 'errors' do
    it 'raises ApiError carrying the server reason in error_message, for an unknown parameter' do
      error = nil
      expect { Live.retrying('hostgroup.get bogus') { Live.session.query(method: 'hostgroup.get', params: { bogusparameter: 1 }) } }.to raise_error(ZabbixApi::ApiError, /bogusparameter/) { |raised| error = raised }
      expect(error.response).to be_a(Hash)
      expect(error.error_message).to match(/bogusparameter/)
    end

    it 'raises HttpError naming the status when the url points at no API' do
      nowhere = Live.url.sub('api_jsonrpc.php', "#{Live.name(klass, 'nowhere')}.php")

      expect { ZabbixApi.connect(url: nowhere, token: Live.token) }.to raise_error(ZabbixApi::HttpError, /HTTP Error: 404/)
    end

    it 'wraps a refused connection as a TransportError that keeps the original as cause' do
      # timeout and no_proxy only bound the attempt: a dropped packet must not cost 60 seconds,
      # and no environment proxy may answer in place of the dead port. Deliberately not wrapped in
      # Live.retrying: a refused connection is this example's measurement, not a transient.
      error = nil
      expect { ZabbixApi.connect(url: 'http://127.0.0.1:1/api_jsonrpc.php', token: Live.token, no_proxy: true, timeout: 5) }.to raise_error(ZabbixApi::TransportError, /Transport error on/) { |raised| error = raised }
      expect(error.cause).to be_a(SystemCallError)
      expect(error.response).to be_nil
    end

    it 'masks an over-long SNMPv3 passphrase the refusal quotes back, in the message, error, error_message and response' do
      passphrase = "spec-passphrase-#{'x' * 60}"
      check = { type: 13, ports: '161', key_: '1.3.6.1.2.1.1.1.0', snmpv3_securityname: 'spec', snmpv3_securitylevel: 2, snmpv3_authprotocol: 0, snmpv3_authpassphrase: passphrase, snmpv3_privprotocol: 0, snmpv3_privpassphrase: 'spec-privpassphrase' }
      error = nil
      expect { Live.retrying('create over-long passphrase') { Live.session.query(method: 'drule.create', params: [{ name: Live.name(klass, 'echo'), iprange: '192.0.2.40', status: 1, dchecks: [check] }])['druleids'].each { |id| Live.owns('drule', id.to_i) } } }
        .to raise_error(ZabbixApi::ApiError, /is too long for field/) { |raised| error = raised }
      expect(error.message).to include('Value \"***\" is too long for field \"snmpv3_authpassphrase\"')
      expect(error.message).not_to include(passphrase)
      expect(error.error['data']).to start_with('Value "***" is too long for field "snmpv3_authpassphrase"')
      expect(error.error_message).to start_with('Application error.: Value "***" is too long for field "snmpv3_authpassphrase"')
      expect(error.error_message).not_to include(passphrase)
      expect(JSON.generate(error.response)).not_to include(passphrase)
    end
  end

  describe 'aftercare' do
    it 'leaves no host, host group or discovery rule under its prefix once torn down, and the standing hosts and proxy still present' do
      Live.teardown

      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('drule', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
