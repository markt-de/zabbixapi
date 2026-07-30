require 'net/http'
require 'json'
require 'openssl'

class ZabbixApi
  class Client
    # API methods that must not carry authentication: no Authorization header is
    # sent for them, and they are reachable before an auth token exists.
    AUTHLESS_METHODS = ['apiinfo.version', 'user.login'].freeze

    # @param (see ZabbixApi::Client#initialize)
    # @return [Hash]
    attr_reader :options

    # @return [Integer]
    def id
      rand(100_000)
    end

    # Returns the API version from the Zabbix Server
    #
    # @return [String]
    def api_version
      @api_version ||= api_request(method: 'apiinfo.version', params: {})
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

    # ZabbixApi::Basic.log does not like @client.options[:debug]
    #
    # @return [boolean]
    def debug?
      !@options || @options[:debug]
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
      unless api_version =~ /^7.\d+\.\d+$/
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
    # The auth token is transported via the Authorization: Bearer header (see
    # {#http_request}), not the JSON-RPC body, as recommended for Zabbix 7.0.
    #
    # @param body [Hash]
    # @return [String]
    def message_json(body)
      message = {
        method: body[:method],
        params: body[:params],
        id: id,
        jsonrpc: '2.0'
      }

      JSON.generate(message)
    end

    # Whether the given API method requires authentication
    #
    # @param method [String]
    # @return [Boolean]
    def auth_required?(method)
      !AUTHLESS_METHODS.include?(method)
    end

    # @param body [String]
    # @param auth_required [Boolean] Whether to attach the Authorization: Bearer header
    # @return [String]
    def http_request(body, auth_required = true)
      uri = URI.parse(@options[:url])

      # set the time out the default (60) or to what the user passed
      timeout = @options[:timeout].nil? ? 60 : @options[:timeout]
      puts "[DEBUG] Timeout for request set to #{timeout} seconds" if @options[:debug]

      http =
        if @proxy_uri
          Net::HTTP.Proxy(@proxy_host, @proxy_port, @proxy_user, @proxy_pass).new(uri.host, uri.port)
        else
          Net::HTTP.new(uri.host, uri.port)
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
      request['Authorization'] = "Bearer #{@auth_token}" if auth_required && @auth_token
      request.body = body

      response = http.request(request)

      raise HttpError.new("HTTP Error: #{response.code} on #{@options[:url]}", response) unless response.code == '200'

      puts "[DEBUG] Get answer: #{response.body}" if @options[:debug]
      response.body
    end

    # @param body [String]
    # @param auth_required [Boolean] Whether the underlying HTTP request must be authenticated
    # @return [Hash, String]
    def _request(body, auth_required = true)
      puts "[DEBUG] Send request: #{body}" if @options[:debug]
      result = JSON.parse(http_request(body, auth_required))
      raise ApiError.new("Server answer API error\n #{JSON.pretty_unparse(result['error'])}\n on request:\n #{pretty_body(body)}", result) if result['error']

      result['result']
    end

    def pretty_body(body)
      parsed_body = JSON.parse(body)

      # If password is in body hide it
      parsed_body['params']['password'] = '***' if parsed_body['params'].is_a?(Hash) && parsed_body['params'].key?('password')

      JSON.pretty_unparse(parsed_body)
    end

    # Execute Zabbix API requests and return response
    #
    # @param body [Hash]
    # @return [Hash, String]
    def api_request(body)
      _request(message_json(body), auth_required?(body[:method]))
    end
  end
end
