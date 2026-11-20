# Contract: ZabbixApi::Client
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/apiinfo,
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/user
#   classes:  connect: one apiinfo.version with the documented empty array, the version gate,
#             ignore_version, a pre-created token against a user.login session | the envelope and
#             its four keys | Authorization: Bearer present, and absent on the three authless
#             methods | basic auth keeps the header and moves the token into the body auth |
#             HttpError on a non-200 status, ApiError on an error body, TransportError for the
#             stdlib failures and for an answer that is not JSON | the quoted request with every
#             params value and the body auth masked, keys and structure kept | a secret a refusal
#             quotes back, the body auth and a macro updated by id included, masked whole in the
#             message and the accessors, other quoted values kept | logout: a no-op under a token,
#             user.logout on a session | proxy, no_proxy, the two timeouts, TLS and verify_ssl |
#             api_version memoised | the request id and the options reader | the debug log
#   not here: the live behaviour of the three authless methods, of basic auth and of a refused
#             login, which the acceptance spec measures; HTTP basic-auth enforcement, a working
#             proxy, verify_ssl against a real TLS endpoint and a real server that is not a 7.x
#             release for ignore_version, which need real endpoints where this spec stubs Net::HTTP;
#             the error accessors themselves, which are classes/errors_spec.rb's subject
require 'spec_helper'

RSpec.describe ZabbixApi::Client do
  url = 'http://zabbix.example.invalid/api_jsonrpc.php'
  https_url = 'https://zabbix.example.invalid/api_jsonrpc.php'
  token = 'spec-client-token-0f13'
  version = '7.0.30'

  let(:http) { instance_double(Net::HTTP) }
  let(:queue) { [] }
  let(:sent) { [] }

  before do
    # initialize reads the environment for a proxy, so every example states what it finds there.
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('http_proxy').and_return(nil)
  end

  # No socket is opened: Net::HTTP is a double answering the queued responses in order, while
  # Net::HTTP::Post stays real, so every header the client sets is read back from the request it
  # actually built. Each request is captured in wire form as it goes out.
  def transport(*answers)
    queue.concat(answers)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(Net::HTTP::Post).to receive(:new).and_call_original
    [:use_ssl=, :verify_mode=, :open_timeout=, :read_timeout=].each { |setter| allow(http).to receive(setter) }
    allow(http).to receive(:request) { |post| answer(post) }
  end

  def answer(post)
    sent << { 'body' => JSON.parse(post.body), 'authorization' => post['Authorization'], 'content_type' => post['Content-Type'] }
    queue.shift || raise("the transport has no answer left for #{post.body}")
  end

  def response(code, body)
    instance_double(Net::HTTPResponse, code: code, body: body, :[] => nil)
  end

  def result(value)
    response('200', JSON.generate({ jsonrpc: '2.0', result: value, id: 1 }))
  end

  def refusal(data, message = 'Invalid params.', code = -32602)
    response('200', JSON.generate({ jsonrpc: '2.0', error: { code: code, message: message, data: data }, id: 1 }))
  end

  # A refusal's data quoting the refused value back, in the form the server uses for an over-long
  # value of some fields.
  def too_long(value, field, limit)
    %(Value "#{value}" is too long for field "#{field}" - #{value.size} characters. Allowed length is #{limit} characters.)
  end

  def methods_sent
    sent.map { |request| request['body']['method'] }
  end

  # The error a refused call raises, so that its accessors can be asserted one per line.
  def refused
    yield
    raise 'the call was answered, not refused'
  rescue ZabbixApi::BaseError => e
    e
  end

  describe 'connecting' do
    it 'asks for the version first, with the documented empty array and no authentication' do
      transport(result(version))
      described_class.new(url: url, token: token)

      expect(methods_sent).to eq(['apiinfo.version'])
      expect(sent.first['body']).to include('jsonrpc' => '2.0', 'method' => 'apiinfo.version', 'params' => [])
      expect(sent.first['body']).not_to have_key('auth')
      expect(sent.first['authorization']).to be_nil
    end

    it 'posts to the path of the url it was given' do
      transport(result(version))
      described_class.new(url: url, token: token)

      expect(Net::HTTP::Post).to have_received(:new).with('/api_jsonrpc.php')
    end

    it 'accepts a 7.0.x server and reports its version' do
      transport(result(version))

      expect(described_class.new(url: url, token: token).api_version).to eq(version)
    end

    it 'refuses a server outside the 7.x line, naming the version it found' do
      transport(result('6.4.0'))

      expect { described_class.new(url: url, token: token) }.to raise_error(ZabbixApi::ApiError, /Zabbix API version: 6\.4\.0 is not supported/)
    end

    it 'refuses a version with a character other than a dot after the 7, naming the version it found' do
      transport(result('7X0.29'))

      expect { described_class.new(url: url, token: token) }.to raise_error(ZabbixApi::ApiError, /7X0\.29 is not supported/)
    end

    it 'connects to an unsupported server under ignore_version, and says so only under debug' do
      transport(result('6.4.0'), result('6.4.0'))

      expect { described_class.new(url: url, token: token, ignore_version: true, debug: true) }.to output(/\[WARNING\] Zabbix API version: 6\.4\.0 is not supported/).to_stdout
      expect { described_class.new(url: url, token: token, ignore_version: true) }.not_to output.to_stdout
    end

    it 'logs in with the documented object when no token is given and carries the session token afterwards' do
      transport(result(version), result('session-2c4f'), result([]))
      client = described_class.new(url: url, user: 'Admin', password: 'spec-password')
      client.api_request(method: 'hostgroup.get', params: {})

      expect(methods_sent).to eq(%w[apiinfo.version user.login hostgroup.get])
      expect(sent[1]['body']['params']).to eq('username' => 'Admin', 'password' => 'spec-password')
      expect(sent[1]['authorization']).to be_nil
      expect(sent.last['authorization']).to eq('Bearer session-2c4f')
    end

    it 'uses a pre-created token as the Bearer credential and calls no login method' do
      transport(result(version), result([]))
      described_class.new(url: url, token: token).api_request(method: 'hostgroup.get', params: {})

      expect(methods_sent).to eq(%w[apiinfo.version hostgroup.get])
      expect(sent.last['authorization']).to eq("Bearer #{token}")
    end

    it 'exposes the options it was built with' do
      transport(result(version))

      expect(described_class.new(url: url, token: token, debug: false).options).to eq(url: url, token: token, debug: false)
    end
  end

  describe '#api_version' do
    it 'is memoised for the life of the client: repeated reads issue no further request' do
      transport(result(version))
      client = described_class.new(url: url, token: token)

      3.times { client.api_version }
      expect(methods_sent).to eq(['apiinfo.version'])
    end
  end

  describe 'the JSON-RPC envelope' do
    it 'carries exactly jsonrpc, method, params and an Integer id, under application/json-rpc, one of the documented content types' do
      transport(result(version), result([]))
      described_class.new(url: url, token: token).api_request(method: 'hostgroup.get', params: { filter: { name: 'x' } })

      call = sent.last
      expect(call['body'].keys.sort).to eq(%w[id jsonrpc method params])
      expect(call['body']).to include('jsonrpc' => '2.0', 'method' => 'hostgroup.get', 'params' => { 'filter' => { 'name' => 'x' } })
      expect(call['body']['id']).to be_an(Integer)
      expect(call['content_type']).to eq('application/json-rpc')
    end

    it 'returns an Integer request id from 0 to 99999' do
      transport(result(version))

      id = described_class.new(url: url, token: token).id
      expect(id).to be_an(Integer)
      expect(id).to be_between(0, 99_999)
    end
  end

  describe 'the unauthenticated methods' do
    it 'names apiinfo.version, user.login and user.checkAuthentication, and only those' do
      transport(result(version))
      client = described_class.new(url: url, token: token)

      expect(described_class::AUTHLESS_METHODS).to eq(%w[apiinfo.version user.login user.checkAuthentication])
      expect(described_class::AUTHLESS_METHODS.map { |method| client.auth_required?(method) }).to eq([false, false, false])
      expect(client.auth_required?('hostgroup.get')).to be(true)
    end

    it 'sends no Authorization header for apiinfo.version and user.checkAuthentication, although a token is available' do
      transport(result(version), result({}), result([]))
      client = described_class.new(url: url, token: token)
      client.api_request(method: 'user.checkAuthentication', params: { token: token })
      client.api_request(method: 'hostgroup.get', params: {})

      expect(sent.map { |request| request['authorization'] }).to eq([nil, nil, "Bearer #{token}"])
    end
  end

  describe 'HTTP basic auth' do
    it 'leaves the Authorization header to the basic credentials and moves the token into the body' do
      transport(result(version), result([]))
      client = described_class.new(url: url, token: token, http_user: 'web', http_password: 'web-secret')
      client.api_request(method: 'hostgroup.get', params: {})

      expect(client.basic_auth?).to be(true)
      expect(sent.last['authorization']).to start_with('Basic ')
      expect(sent.last['authorization'].split.last.unpack1('m0')).to eq('web:web-secret')
      expect(sent.last['body']['auth']).to eq(token)
    end

    it 'keeps the body auth property off an authless method and the basic credentials in the header' do
      transport(result(version), result({}))
      client = described_class.new(url: url, token: token, http_user: 'web', http_password: 'web-secret')
      client.api_request(method: 'user.checkAuthentication', params: { token: token })

      expect(sent.last['body']['method']).to eq('user.checkAuthentication')
      expect(sent.last['body']).not_to have_key('auth')
      expect(sent.last['authorization']).to start_with('Basic ')
    end
  end

  describe 'errors' do
    it 'raises HttpError naming the status and the url when the answer is not a 200' do
      transport(result(version), response('404', 'Not Found'))
      client = described_class.new(url: url, token: token)

      expect { client.api_request(method: 'hostgroup.get', params: {}) }.to raise_error(ZabbixApi::HttpError, %r{HTTP Error: 404 on http://zabbix\.example\.invalid/api_jsonrpc\.php})
    end

    it 'keeps the HTTP response itself on an HttpError, not a parsed body' do
      transport(result(version), response('500', 'Internal Server Error'))
      client = described_class.new(url: url, token: token)

      error = refused { client.api_request(method: 'hostgroup.get', params: {}) }
      expect(error.response.code).to eq('500')
    end

    it 'raises ApiError when the body carries an error' do
      transport(result(version), refusal('Invalid parameter "/1/name": cannot be empty.'))
      client = described_class.new(url: url, token: token)

      expect { client.api_request(method: 'hostgroup.create', params: [{ name: '' }]) }.to raise_error(ZabbixApi::ApiError, /Server answer API error/)
    end

    it 'puts the parsed body on response, the error object on error, and its message and data joined on error_message' do
      data = 'Invalid parameter "/1/name": cannot be empty.'
      transport(result(version), refusal(data))
      client = described_class.new(url: url, token: token)

      error = refused { client.api_request(method: 'hostgroup.create', params: [{ name: '' }]) }
      expect(error.error).to eq('code' => -32602, 'message' => 'Invalid params.', 'data' => data)
      expect(error.error_message).to eq("Invalid params.: #{data}")
      expect(error.response['error']).to eq(error.error)
    end

    # A failure that never became a JSON-RPC exchange is a TransportError, so one
    # `rescue ZabbixApi::BaseError` covers a dead connection as well as a refusal.
    # Client::TRANSPORT_ERRORS names parent classes, which cover their subclasses, so the list below
    # also raises two subclasses: Errno::ECONNREFUSED, a SystemCallError, and EOFError, an IOError.
    [Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, IOError, EOFError].each do |failure|
      it "wraps #{failure} as a TransportError that keeps the original as cause" do
        transport(result(version))
        client = described_class.new(url: url, token: token)
        allow(http).to receive(:request).and_raise(failure)

        error = refused { client.api_request(method: 'hostgroup.get', params: {}) }
        expect(error).to be_a(ZabbixApi::TransportError)
        expect(error.message).to match(/\ATransport error on #{Regexp.escape(url)}: #{failure}: /)
        expect(error.cause).to be_a(failure)
        expect(error.response).to be_nil
      end
    end

    it 'wraps a url that will not parse as a TransportError with the parse error as cause' do
      error = refused { described_class.new(url: 'http://zabbix example.invalid/api_jsonrpc.php', token: token) }

      expect(error).to be_a(ZabbixApi::TransportError)
      expect(error.cause).to be_a(URI::InvalidURIError)
    end

    it 'wraps a 200 whose body is not JSON as a TransportError with the parse error as cause' do
      transport(response('200', '<html><body>502 Bad Gateway</body></html>'))

      error = refused { described_class.new(url: url, token: token) }
      expect(error).to be_a(ZabbixApi::TransportError)
      expect(error.message).to match(/\AMalformed response from #{Regexp.escape(url)}: /)
      expect(error.cause).to be_a(JSON::ParserError)
    end
  end

  describe 'redaction of the quoted request' do
    it 'masks the password of a refused user.login' do
      transport(result(version), refusal('Incorrect user name or password or account is temporarily blocked.'))

      expect { described_class.new(url: url, user: 'Admin', password: 'spec-password') }.to raise_error(ZabbixApi::ApiError, /"password": "\*\*\*"/) { |error| expect(error.message).not_to include('spec-password') }
    end

    it 'masks the token parameter of user.checkAuthentication' do
      transport(result(version), refusal('Session terminated, re-login, please.'))
      client = described_class.new(url: url, token: token)

      expect { client.api_request(method: 'user.checkAuthentication', params: { token: token }) }.to raise_error(ZabbixApi::ApiError, /"token": "\*\*\*"/) { |error| expect(error.message).not_to include(token) }
    end

    it 'masks the body auth property under basic auth' do
      transport(result(version), refusal('No permissions to referred object or it does not exist!'))
      client = described_class.new(url: url, token: token, http_user: 'web', http_password: 'web-secret')

      expect { client.api_request(method: 'hostgroup.get', params: {}) }.to raise_error(ZabbixApi::ApiError, /"auth": "\*\*\*"/) { |error| expect(error.message).not_to include(token) }
    end

    it 'renders a refusal whose params are an Array rather than an object' do
      transport(result(version), refusal('Incorrect method "user.logoutt".', 'Method not found.', -32601))
      client = described_class.new(url: url, token: token)

      expect { client.api_request(method: 'user.logout', params: []) }.to raise_error(ZabbixApi::ApiError, /Method not found/)
    end

    it 'masks every params value, keeping the keys, the Array positions and the nesting, and leaves method and jsonrpc as sent' do
      transport(result(version), refusal('Invalid parameter "/1": unexpected parameter "ids".'))
      client = described_class.new(url: url, token: token)

      error = refused { client.api_request(method: 'hostgroup.create', params: [{ name: 'spec-group', ids: [7, 8], flags: { on: true, off: nil } }]) }
      quoted = JSON.parse(error.message.split("\n on request:\n").last)
      expect(quoted).to include('method' => 'hostgroup.create', 'jsonrpc' => '2.0')
      expect(quoted['params']).to eq([{ 'name' => '***', 'ids' => ['***', '***'], 'flags' => { 'on' => '***', 'off' => '***' } }])
    end

    it 'masks the sessionid parameter of user.checkAuthentication' do
      sessionid = 'spec-session-5f57'
      transport(result(version), refusal('Session terminated, re-login, please.'))
      client = described_class.new(url: url, token: token)

      expect { client.api_request(method: 'user.checkAuthentication', params: { sessionid: sessionid }) }.to raise_error(ZabbixApi::ApiError, /"sessionid": "\*\*\*"/) { |error| expect(error.message).not_to include(sessionid) }
    end
  end

  describe 'secrets a refusal quotes back' do
    it 'masks an IPMI password the refusal quotes back, in the message and in error, error_message and response' do
      secret = 'spec-ipmi-password-0123'
      transport(result(version), refusal(too_long(secret, 'ipmi_password', 20), 'Application error.', -32500))
      client = described_class.new(url: url, token: token)

      error = refused { client.api_request(method: 'host.create', params: [{ host: 'spec-host', ipmi_password: secret }]) }
      expect(error.error_message).to eq('Application error.: Value "***" is too long for field "ipmi_password" - 23 characters. Allowed length is 20 characters.')
      expect(error.error).to eq(error.response['error'])
      expect(error.message).not_to include(secret)
      expect(JSON.generate(error.response)).not_to include(secret)
    end

    it "masks an SNMP community sent in an interface's details that the refusal quotes back" do
      community = "spec-community-#{'x' * 60}"
      transport(result(version), refusal(too_long(community, 'community', 64), 'Application error.', -32500))
      client = described_class.new(url: url, token: token)

      error = refused { client.api_request(method: 'host.create', params: [{ host: 'spec-host', interfaces: [{ type: 2, details: { version: 2, community: community } }] }]) }
      expect(error.error_message).to eq('Application error.: Value "***" is too long for field "community" - 75 characters. Allowed length is 64 characters.')
      expect(error.message).not_to include(community)
    end

    it "masks a secret macro's value the refusal quotes back, and leaves a text macro's value as the refusal has it" do
      # Both refusals are scripted: Zabbix does not quote an over-long secret macro value back.
      secret = "spec-secret-macro-#{'x' * 2040}"
      text = "spec-text-macro-#{'x' * 2040}"
      transport(result(version), refusal(too_long(secret, 'value', 2048), 'Application error.', -32500), refusal(too_long(text, 'value', 2048), 'Application error.', -32500))
      client = described_class.new(url: url, token: token)

      secret_error = refused { client.api_request(method: 'usermacro.create', params: { hostid: 10, macro: '{$SPEC_SECRET}', value: secret, type: 1 }) }
      text_error = refused { client.api_request(method: 'usermacro.create', params: { hostid: 10, macro: '{$SPEC_TEXT}', value: text, type: 0 }) }
      expect(secret_error.error_message).to eq('Application error.: Value "***" is too long for field "value" - 2058 characters. Allowed length is 2048 characters.')
      expect(secret_error.message).not_to include(secret)
      expect(text_error.error_message).to include(%("#{text}"))
    end

    it "masks a secret macro's value the refusal quotes back, in an update by hostmacroid and in one by globalmacroid" do
      # Both refusals are scripted: Zabbix does not quote an over-long secret macro value back.
      host_secret = "spec-host-macro-#{'x' * 2040}"
      global_secret = "spec-global-macro-#{'x' * 2040}"
      transport(result(version), refusal(too_long(host_secret, 'value', 2048), 'Application error.', -32500), refusal(too_long(global_secret, 'value', 2048), 'Application error.', -32500))
      client = described_class.new(url: url, token: token)

      host_error = refused { client.api_request(method: 'usermacro.update', params: { hostmacroid: 10, value: host_secret, type: 1 }) }
      global_error = refused { client.api_request(method: 'usermacro.updateglobal', params: { globalmacroid: 2, value: global_secret, type: 1 }) }
      expect(host_error.error_message).to eq('Application error.: Value "***" is too long for field "value" - 2056 characters. Allowed length is 2048 characters.')
      expect(global_error.error_message).to eq('Application error.: Value "***" is too long for field "value" - 2058 characters. Allowed length is 2048 characters.')
      expect(host_error.message).not_to include(host_secret)
      expect(global_error.message).not_to include(global_secret)
    end

    it 'masks the token from the body auth under basic auth where the refusal quotes it back' do
      # The refusal is scripted: it stands for any answer that quotes the token.
      transport(result(version), refusal(%(Session "#{token}" is not valid.)))
      client = described_class.new(url: url, token: token, http_user: 'web', http_password: 'web-secret')

      error = refused { client.api_request(method: 'hostgroup.get', params: {}) }
      expect(error.error_message).to eq('Invalid params.: Session "***" is not valid.')
      expect(error.message).not_to include(token)
      expect(JSON.generate(error.response)).not_to include(token)
    end

    it 'masks an SNMP community whole although it ends in the IPMI password the same request carries' do
      # The community ends in a double quote and the IPMI password, so the password's quoted form
      # stands inside the community's.
      community = %(spec-#{'p' * 60}"spec-q)
      transport(result(version), refusal(too_long(community, 'community', 64), 'Application error.', -32500))
      client = described_class.new(url: url, token: token)

      error = refused { client.api_request(method: 'host.create', params: [{ host: 'spec-host', ipmi_password: 'spec-q', interfaces: [{ type: 2, details: { version: 2, community: community } }] }]) }
      expect(error.error_message).to eq('Application error.: Value "***" is too long for field "community" - 72 characters. Allowed length is 64 characters.')
      expect(error.message).not_to include('p' * 60)
      expect(JSON.generate(error.response)).not_to include('p' * 60)
    end

    it 'leaves a quoted value that is no secret, and a secret the refusal names without quotes, as the refusal has them' do
      transport(result(version), refusal('Host with the same name "spec-host" already exists.'), refusal('Value spec-bare-secret is refused.'))
      client = described_class.new(url: url, token: token)

      name_error = refused { client.api_request(method: 'host.create', params: [{ host: 'spec-host', groups: [{ groupid: 2 }] }]) }
      bare_error = refused { client.api_request(method: 'host.create', params: [{ host: 'spec-bare', ipmi_password: 'spec-bare-secret' }]) }
      expect(name_error.error_message).to eq('Invalid params.: Host with the same name "spec-host" already exists.')
      expect(bare_error.error_message).to eq('Invalid params.: Value spec-bare-secret is refused.')
    end
  end

  describe '#logout' do
    it 'is a no-op under token auth: it returns true and sends nothing' do
      transport(result(version))
      client = described_class.new(url: url, token: token)

      expect(client.logout).to be(true)
      expect(methods_sent).to eq(['apiinfo.version'])
    end

    it 'ends a login session with the documented empty array and returns what the server answered' do
      transport(result(version), result('session-2c4f'), result(true))
      client = described_class.new(url: url, user: 'Admin', password: 'spec-password')

      expect(client.logout).to be(true)
      expect(sent.last['body']).to include('method' => 'user.logout', 'params' => [])
      expect(sent.last['authorization']).to eq('Bearer session-2c4f')
    end
  end

  describe 'transport options' do
    it 'sets both timeouts to 60 seconds by default and to the option where one is given' do
      transport(result(version), result(version))
      described_class.new(url: url, token: token)
      described_class.new(url: url, token: token, timeout: 7)

      expect(http).to have_received(:open_timeout=).with(60).once
      expect(http).to have_received(:read_timeout=).with(60).once
      expect(http).to have_received(:open_timeout=).with(7).once
      expect(http).to have_received(:read_timeout=).with(7).once
    end

    it 'hands Net::HTTP an explicit nil proxy under no_proxy, although the environment names one' do
      allow(ENV).to receive(:[]).with('http_proxy').and_return('http://proxy.example.invalid:3128')
      transport(result(version))
      described_class.new(url: url, token: token, no_proxy: true)

      expect(Net::HTTP).to have_received(:new).with('zabbix.example.invalid', 80, nil)
    end

    it 'routes through the environment proxy, its credentials included, when no_proxy is not set' do
      allow(ENV).to receive(:[]).with('http_proxy').and_return('http://proxyuser:proxypass@proxy.example.invalid:3128')
      proxied = class_double(Net::HTTP, new: http)
      allow(Net::HTTP).to receive(:Proxy).and_return(proxied)
      transport(result(version))
      described_class.new(url: url, token: token)

      expect(Net::HTTP).to have_received(:Proxy).with('proxy.example.invalid', 3128, 'proxyuser', 'proxypass')
      expect(proxied).to have_received(:new).with('zabbix.example.invalid', 80)
    end

    it 'leaves TLS alone for an http url' do
      transport(result(version))
      described_class.new(url: url, token: token)

      expect(http).not_to have_received(:use_ssl=)
    end

    it 'turns TLS on for an https url and sets VERIFY_NONE by default' do
      transport(result(version))
      described_class.new(url: https_url, token: token)

      expect(http).to have_received(:use_ssl=).with(true)
      expect(http).to have_received(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
    end

    it 'sets VERIFY_PEER under verify_ssl' do
      transport(result(version))
      described_class.new(url: https_url, token: token, verify_ssl: true)

      expect(http).to have_received(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
    end

    it 'prints the request, the timeout and the answer under debug' do
      transport(result(version))

      expect { described_class.new(url: url, token: token, debug: true) }.to output(/\[DEBUG\] Send request: .*apiinfo\.version.*\[DEBUG\] Timeout for request set to 60 seconds.*\[DEBUG\] Get answer: .*7\.0\.30/m).to_stdout
    end
  end
end
