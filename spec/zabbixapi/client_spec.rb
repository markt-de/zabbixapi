require 'spec_helper'

describe ZabbixApi::Client do
  let(:url) { 'http://localhost/api_jsonrpc.php' }
  let(:options) { { url: url, no_proxy: true } }
  let(:client) { described_class.new(options) }

  # Stub the HTTP transport so Client.new runs end-to-end without a network:
  # apiinfo.version -> 7.0.0, user.login -> sessiontoken, anything else -> ok.
  def stub_transport
    allow_any_instance_of(described_class).to receive(:http_request) do |_instance, body, _auth_required|
      case JSON.parse(body)['method']
      when 'apiinfo.version' then '{"result":"7.0.0"}'
      when 'user.login' then '{"result":"sessiontoken"}'
      else '{"result":"ok"}'
      end
    end
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('http_proxy').and_return(nil)
    stub_transport
  end

  describe '#id' do
    it 'is a random integer drawn from rand(100_000)' do
      expect(client.id).to be_a(Integer)
      expect(client).to receive(:rand).with(100_000).and_return(42)
      expect(client.id).to eq 42
    end
  end

  describe '#api_version' do
    it 'fetches the version via apiinfo.version and memoizes it' do
      expect(client.api_version).to eq '7.0.0'
      expect(client).not_to receive(:api_request)
      expect(client.api_version).to eq '7.0.0'
    end
  end

  describe '#auth' do
    let(:options) { { url: url, no_proxy: true, user: 'Admin', password: 'secret' } }

    it 'logs in via user.login with username and password' do
      expect(client).to receive(:api_request).with(
        method: 'user.login',
        params: { username: 'Admin', password: 'secret' }
      ).and_return('sessiontoken')
      expect(client.auth).to eq 'sessiontoken'
    end
  end

  describe '#auth_required?' do
    it 'is false for the authless methods' do
      expect(client.auth_required?('apiinfo.version')).to be false
      expect(client.auth_required?('user.login')).to be false
    end

    it 'is true for every other method (including user.logout)' do
      expect(client.auth_required?('host.get')).to be true
      expect(client.auth_required?('user.logout')).to be true
    end
  end

  describe '#message_json' do
    before { allow(client).to receive(:id).and_return(9090) }

    it 'builds a JSON-RPC 2.0 envelope' do
      expect(JSON.parse(client.message_json(method: 'host.get', params: 'p'))).to eq(
        'method' => 'host.get', 'params' => 'p', 'id' => 9090, 'jsonrpc' => '2.0'
      )
    end

    it 'never puts the auth token in the body (it travels in the header)' do
      %w[host.get user.logout apiinfo.version user.login].each do |method|
        expect(JSON.parse(client.message_json(method: method, params: []))).not_to have_key('auth')
      end
    end
  end

  describe '#logout' do
    context 'with a session (user.login) token' do
      it 'revokes the session via user.logout' do
        expect(client).to receive(:api_request).with(method: 'user.logout', params: []).and_return(true)
        expect(client.logout).to eq true
      end
    end

    context 'with a pre-created API token' do
      let(:options) { { url: url, no_proxy: true, token: 'apitoken' } }

      it 'is a no-op and does not hit the API' do
        built = client
        expect(built).not_to receive(:api_request)
        expect(built.logout).to be true
      end
    end
  end

  describe '#initialize' do
    context 'version gate' do
      it 'raises unless the server is 7.x' do
        allow_any_instance_of(described_class).to receive(:api_version).and_return('6.4.0')
        expect { client }.to raise_error(ZabbixApi::ApiError, /is not supported/)
      end

      it 'continues when ignore_version is set' do
        allow_any_instance_of(described_class).to receive(:api_version).and_return('6.4.0')
        expect { described_class.new(options.merge(ignore_version: true)) }.not_to raise_error
      end
    end

    context 'authentication mode' do
      it 'logs in for a session token when no token is supplied' do
        expect(client.instance_variable_get(:@auth_token)).to eq 'sessiontoken'
        expect(client.instance_variable_get(:@token_auth)).to be false
      end

      it 'uses a pre-created API token and skips user.login' do
        expect_any_instance_of(described_class).not_to receive(:auth)
        c = described_class.new(options.merge(token: 'apitoken'))
        expect(c.instance_variable_get(:@auth_token)).to eq 'apitoken'
        expect(c.instance_variable_get(:@token_auth)).to be true
      end
    end

    context 'proxy handling' do
      let(:proxy) { 'https://puser:ppass@proxy.example.com' }

      context 'when http_proxy is set and no_proxy is false' do
        let(:options) { { url: url, no_proxy: false } }
        before { allow(ENV).to receive(:[]).with('http_proxy').and_return(proxy) }

        it 'parses the proxy settings' do
          expect(client.instance_variable_get(:@proxy_host)).to eq 'proxy.example.com'
          expect(client.instance_variable_get(:@proxy_port)).to eq 443
          expect(client.instance_variable_get(:@proxy_user)).to eq 'puser'
          expect(client.instance_variable_get(:@proxy_pass)).to eq 'ppass'
        end
      end

      context 'when no_proxy is true' do
        before { allow(ENV).to receive(:[]).with('http_proxy').and_return(proxy) }

        it 'ignores the proxy' do
          expect(client.instance_variable_get(:@proxy_uri)).to be_nil
        end
      end
    end
  end

  describe '#http_request' do
    let(:post) { double('post') }
    let(:http) { double('http') }
    let(:response) { double('response', code: '200', body: '{"result":"ok"}') }

    before do
      # Build the client without the transport stub touching the real http_request.
      allow_any_instance_of(described_class).to receive(:api_version).and_return('7.0.0')
      allow_any_instance_of(described_class).to receive(:auth).and_return('sessiontoken')
      allow_any_instance_of(described_class).to receive(:http_request).and_call_original

      allow(Net::HTTP).to receive(:new).with('localhost', 80).and_return(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).with(post).and_return(response)
      allow(response).to receive(:[]) # HttpError reads response['error']
      allow(Net::HTTP::Post).to receive(:new).with('/api_jsonrpc.php').and_return(post)
      allow(post).to receive(:add_field)
      allow(post).to receive(:basic_auth)
      allow(post).to receive(:[]=)
      allow(post).to receive(:body=)
    end

    it 'attaches the Authorization: Bearer header on authenticated requests' do
      expect(post).to receive(:[]=).with('Authorization', 'Bearer sessiontoken')
      client.http_request('{"method":"host.get"}', true)
    end

    it 'omits the Authorization header on unauthenticated requests' do
      expect(post).not_to receive(:[]=).with('Authorization', anything)
      client.http_request('{"method":"apiinfo.version"}', false)
    end

    it 'returns the response body on 200' do
      expect(client.http_request('{}')).to eq '{"result":"ok"}'
    end

    context 'when the response is not 200' do
      let(:response) { double('response', code: '500', body: 'boom') }

      it 'raises HttpError' do
        expect { client.http_request('{}') }.to raise_error(ZabbixApi::HttpError, /HTTP Error: 500/)
      end
    end

    context 'with HTTP basic auth credentials' do
      let(:options) { { url: url, no_proxy: true, http_user: 'hu', http_password: 'hp' } }

      it 'sets basic auth' do
        expect(post).to receive(:basic_auth).with('hu', 'hp')
        client.http_request('{}')
      end
    end
  end

  describe '#_request' do
    before { allow(client).to receive(:http_request).and_return('{"result":"ok"}') }

    it 'returns the parsed result' do
      expect(client._request('{"method":"host.get"}')).to eq 'ok'
    end

    it 'passes auth_required through to http_request' do
      expect(client).to receive(:http_request).with('{"method":"x"}', false).and_return('{"result":"ok"}')
      client._request('{"method":"x"}', false)
    end

    context 'when the response contains an error' do
      before { allow(client).to receive(:http_request).and_return('{"error":{"message":"bad","data":"nope"}}') }

      it 'raises ApiError' do
        expect { client._request('{"method":"x"}') }.to raise_error(ZabbixApi::ApiError, /Server answer API error/)
      end
    end
  end

  describe '#api_request' do
    it 'sends the message and marks non-authless methods as authenticated' do
      body = { method: 'host.get', params: {} }
      allow(client).to receive(:message_json).with(body).and_return('json')
      expect(client).to receive(:_request).with('json', true).and_return('ok')
      expect(client.api_request(body)).to eq 'ok'
    end

    it 'marks apiinfo.version as unauthenticated' do
      body = { method: 'apiinfo.version', params: {} }
      allow(client).to receive(:message_json).with(body).and_return('json')
      expect(client).to receive(:_request).with('json', false).and_return('7.0.0')
      client.api_request(body)
    end
  end

  describe '#pretty_body' do
    it 'redacts a password param' do
      body = '{"params":{"password":"secret"}}'
      expect(client.pretty_body(body)).to include('***')
      expect(client.pretty_body(body)).not_to include('secret')
    end

    it 'leaves bodies without a password untouched' do
      expect(JSON.parse(client.pretty_body('{"params":"x"}'))).to eq('params' => 'x')
    end
  end
end
