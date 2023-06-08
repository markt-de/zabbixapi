require 'net/http'
require 'json'
require 'openssl'

class ZabbixApi
  class Client
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
    # @return [Hash]
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
      return ! @options || @options[:debug]
    end

    # Log out from the Zabbix Server
    #
    # @return [Boolean]
    #
    def logout
      api_request(
	 :method => 'user.logout',
	 :params => []
      )
    end

    # Initializes a new Client object
    #
    # @param options [Hash]
    # @option opts [String] :url The url of zabbixapi(example: 'http://localhost/zabbix/api_jsonrpc.php')
    # @option opts [String] :user
    # @option opts [String] :password
    # @option opts [String] :http_user A user for basic auth.(optional)
    # @option opts [String] :http_password A password for basic auth.(optional)
    # @option opts [Integer] :timeout Set timeout for requests in seconds.(default: 60)
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
      unless api_version =~ %r{^5.[0|2]\.\d+$}
        message = "Zabbix API version: #{api_version} is not supported by this version of zabbixapi"
        if @options[:ignore_version]
          puts "[WARNING] #{message}" if @options[:debug]
        else
          raise ZabbixApi::ApiError.new(message)
        end
      end

      @auth_hash = auth
    end

    # Convert message body to JSON string for the Zabbix API
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

      message[:auth] = @auth_hash unless body[:method] == 'apiinfo.version' || body[:method] == 'user.login'

      JSON.generate(message)
    end

    # @param body [String]
    # @return [String]
    def http_request(body)
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
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      http.open_timeout = timeout
      http.read_timeout = timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request.basic_auth @options[:http_user], @options[:http_password] if @options[:http_user]
      request.add_field('Content-Type', 'application/json-rpc')
      request.body = body

      response = http.request(request)

      raise HttpError.new("HTTP Error: #{response.code} on #{@options[:url]}", response) unless response.code == '200'

      puts "[DEBUG] Get answer: #{response.body}" if @options[:debug]
      response.body
    end

    # @param body [String]
    # @return [Hash, String]
    def _request(body)
      puts "[DEBUG] Send request: #{body}" if @options[:debug]
      result = JSON.parse(http_request(body))
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
      _request message_json(body)
    end
  end
end
