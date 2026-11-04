require 'net/http'
require 'json'
require 'openssl'

class ZabbixApi
  # The JSON-RPC 2.0 client: checks the server version, authenticates and sends every request over HTTP.
  class Client
    # API methods called without authentication: no Authorization header is sent for them,
    # they are reachable before a token exists, and the server refuses them when the header
    # is present.
    AUTHLESS_METHODS = ['apiinfo.version', 'user.login', 'user.checkAuthentication'].freeze

    # Stdlib exceptions {#http_request} converts into {TransportError}, so one
    # `rescue ZabbixApi::BaseError` covers transport failures and API errors alike. Parent
    # classes cover their subclasses: every Errno::* is a SystemCallError, EOFError an IOError.
    # A response that is not JSON is converted in {#_request}.
    TRANSPORT_ERRORS = [SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, IOError, URI::InvalidURIError].freeze

    # Request properties that carry a secret in the Zabbix 7.0 API: passwords, tokens, session
    # ids, PSKs with their identities, and SNMP credentials.
    SECRET_KEYS = %w[password passwd current_passwd token sessionid tls_psk tls_psk_identity ipmi_password http_password ssl_key_password bind_password test_password client_secret community snmp_community authpassphrase privpassphrase snmpv3_authpassphrase snmpv3_privpassphrase].freeze

    # @param (see ZabbixApi::Client#initialize)
    # @return [Hash]
    attr_reader :options

    # @return [Integer]
    def id
      rand(100_000)
    end

    # Returns the API version of the Zabbix server, requested once per client
    #
    # @return [String]
    def api_version
      @api_version ||= api_request(method: 'apiinfo.version', params: [])
      @api_version
    end

    # Log in to the Zabbix Server and generate an auth token using the API
    #
    # @return [String] The session authentication token
    def auth
      api_request(
        method: 'user.login',
        params: {
          username: @options[:user],
          password: @options[:password]
        }
      )
    end

    # Log out from the Zabbix Server
    #
    # When authenticated with a pre-created API token, logout is a no-op: the token
    # belongs to the caller and must not be invalidated by the client.
    #
    # @return [Boolean]
    def logout
      return true if @token_auth

      api_request(
        method: 'user.logout',
        params: []
      )
    end

    # Initializes a new Client object
    #
    # @param options [Hash]
    # @option options [String] :url The url of the Zabbix API (example: 'http://localhost/zabbix/api_jsonrpc.php')
    # @option options [String] :user Username for user.login authentication
    # @option options [String] :password Password for user.login authentication
    # @option options [String] :token Pre-created API token; when supplied, user.login is skipped and this token is used
    # @option options [String] :http_user A user for HTTP basic auth (optional)
    # @option options [String] :http_password A password for HTTP basic auth (optional)
    # @option options [Integer] :timeout Set timeout for requests in seconds (default: 60)
    # @option options [Boolean] :verify_ssl Verify the server's TLS certificate (default: false)
    # @option options [Boolean] :debug Print requests, answers and warnings to stdout (default: false)
    # @option options [Boolean] :no_proxy Ignore the http_proxy environment variable (default: false)
    # @option options [Boolean] :ignore_version Connect even when the server is not a 7.x release (default: false)
    #
    # @return [ZabbixApi::Client]
    def initialize(options = {})
      @options = options
      if !ENV['http_proxy'].nil? && options[:no_proxy] != true
        @proxy_uri = URI.parse(ENV['http_proxy'])
        @proxy_host = @proxy_uri.host
        @proxy_port = @proxy_uri.port
        @proxy_user, @proxy_pass = @proxy_uri.userinfo.split(/:/) if @proxy_uri.userinfo
      end
      unless api_version =~ /\A7\.\d+\.\d+\z/
        message = "Zabbix API version: #{api_version} is not supported by this version of zabbixapi"
        raise ZabbixApi::ApiError.new(message) unless @options[:ignore_version]

        puts "[WARNING] #{message}" if @options[:debug]

      end

      # Use a pre-created API token when supplied, otherwise log in for a session token.
      @token_auth = !@options[:token].nil?
      @auth_token = @options[:token] || auth
    end

    # Convert message body to JSON string for the Zabbix API
    #
    # The auth token normally travels in the Authorization: Bearer header (see
    # {#http_request}), as recommended for Zabbix 7.0, and not in the JSON-RPC body. The one
    # exception is HTTP basic auth, which occupies that header; see {#basic_auth?}.
    #
    # @param body [Hash]
    # @param auth_required [Boolean] Whether this method needs authentication at all
    # @return [String]
    def message_json(body, auth_required = false)
      message = {
        method: body[:method],
        params: body[:params],
        id: id,
        jsonrpc: '2.0'
      }
      message[:auth] = @auth_token if auth_required && @auth_token && basic_auth?

      JSON.generate(message)
    end

    # Whether the given API method requires authentication
    #
    # @param method [String]
    # @return [Boolean]
    def auth_required?(method)
      !AUTHLESS_METHODS.include?(method)
    end

    # Whether HTTP basic auth occupies the Authorization header
    #
    # HTTP allows one Authorization header, so with basic credentials the API token is sent in
    # the body `auth` property instead. That property is deprecated in Zabbix 7.0 and is used
    # only in this case.
    #
    # @return [Boolean]
    def basic_auth?
      !@options[:http_user].nil?
    end

    # @param body [String]
    # @param auth_required [Boolean] Whether to attach the Authorization: Bearer header
    # @raise [HttpError] when the server answers with a status other than 200
    # @raise [TransportError] when the request never completed: connection, DNS, TLS, a timeout,
    #   or a url that will not parse
    # @return [String]
    def http_request(body, auth_required = true)
      uri = URI.parse(@options[:url])

      timeout = @options[:timeout].nil? ? 60 : @options[:timeout]
      puts "[DEBUG] Timeout for request set to #{timeout} seconds" if @options[:debug]

      http =
        if @proxy_uri
          Net::HTTP.Proxy(@proxy_host, @proxy_port, @proxy_user, @proxy_pass).new(uri.host, uri.port)
        else
          # An explicit nil: Net::HTTP.new's p_addr defaults to :ENV, which would pick up
          # http_proxy from the environment despite `no_proxy: true`.
          Net::HTTP.new(uri.host, uri.port, nil)
        end

      if uri.scheme == 'https'
        http.use_ssl = true
        http.verify_mode = @options[:verify_ssl] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      end

      http.open_timeout = timeout
      http.read_timeout = timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request.basic_auth @options[:http_user], @options[:http_password] if @options[:http_user]
      request.add_field('Content-Type', 'application/json-rpc')
      request['Authorization'] = "Bearer #{@auth_token}" if auth_required && @auth_token && !basic_auth?
      request.body = body

      response = http.request(request)

      raise HttpError.new("HTTP Error: #{response.code} on #{@options[:url]}", response) unless response.code == '200'

      puts "[DEBUG] Get answer: #{response.body}" if @options[:debug]
      response.body
    rescue *TRANSPORT_ERRORS => e
      raise TransportError.new("Transport error on #{@options[:url]}: #{e.class}: #{e.message}")
    end

    # @param body [String]
    # @param auth_required [Boolean] Whether the underlying HTTP request must be authenticated
    # @raise [ApiError] when the answer carries a JSON-RPC error object; its message quotes the
    #   request through {#pretty_body}, and each secret the request carried, as {BaseError} names
    #   them, reads '***' wherever the answer quotes it, in the accessors as in the message
    # @raise [TransportError] when the answer is not JSON at all
    # @return [Hash, Array, String, Boolean] the JSON-RPC result
    def _request(body, auth_required = true)
      puts "[DEBUG] Send request: #{body}" if @options[:debug]
      answer = http_request(body, auth_required)
      result =
        begin
          JSON.parse(answer)
        rescue JSON::ParserError => e
          raise TransportError.new("Malformed response from #{@options[:url]}: #{e.message}")
        end
      raise api_error(body, result) if result['error']

      result['result']
    end

    # Render a request body for error output with every params value and the auth masked
    #
    # @param body [String] The JSON request body as it was sent
    # @return [String] Pretty-printed JSON whose params keep their keys and structure, every value
    #   in them and the top-level auth replaced by '***'
    def pretty_body(body)
      parsed_body = JSON.parse(body)

      parsed_body['params'] = mask(parsed_body['params']) if parsed_body.key?('params')
      parsed_body['auth'] = '***' if parsed_body.key?('auth')

      JSON.pretty_unparse(parsed_body)
    end

    # Execute Zabbix API requests and return response
    #
    # @param body [Hash]
    # @return [Hash, Array, String, Boolean] the JSON-RPC result
    def api_request(body)
      auth_required = auth_required?(body[:method])
      _request(message_json(body, auth_required), auth_required)
    end

  private

    # The ApiError for an answer carrying a JSON-RPC error object: the answer scrubbed of the
    # secrets in the request's params and of its body auth, the longest first so that no shorter
    # secret splits a longer one containing it, and the request quoted through {#pretty_body}
    def api_error(body, result)
      request = JSON.parse(body)
      secrets = secrets_in(request['params']) + [request['auth']].grep(String).reject(&:empty?)
      answer = scrub(result, secrets.sort_by { |secret| -secret.length })
      ApiError.new("Server answer API error\n #{JSON.pretty_unparse(answer['error'])}\n on request:\n #{pretty_body(body)}", answer)
    end

    # Every value in a params structure replaced by '***', Hash keys and Array positions kept
    def mask(value)
      case value
      when Hash then value.transform_values { |item| mask(item) }
      when Array then value.map { |item| mask(item) }
      else '***'
      end
    end

    # The secrets a params structure carries at any depth, as strings: every value under a
    # SECRET_KEYS name, and the value of a user macro of type 1, a secret macro, in a Hash carrying
    # macro, hostmacroid or globalmacroid, where it is a non-empty String or a Numeric
    def secrets_in(value)
      case value
      when Hash
        own = value.slice(*SECRET_KEYS).values
        own << value['value'] if value['type'].to_s == '1' && value.keys.intersect?(%w[macro hostmacroid globalmacroid])
        own.grep(String).reject(&:empty?) + own.grep(Numeric).map(&:to_s) + value.values.flat_map { |item| secrets_in(item) }
      when Array then value.flat_map { |item| secrets_in(item) }
      else []
      end
    end

    # Every string in a parsed answer with each secret replaced by '***' where it stands in double
    # quotes, the form in which the server's messages quote a value
    def scrub(value, secrets)
      case value
      when Hash then value.transform_values { |item| scrub(item, secrets) }
      when Array then value.map { |item| scrub(item, secrets) }
      when String then secrets.reduce(value) { |text, secret| text.gsub("\"#{secret}\"", '"***"') }
      else value
      end
    end
  end
end
