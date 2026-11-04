class ZabbixApi
  # Generic CRUD for one Zabbix API object, built on a subclass's {#method_name} and {#identify}.
  #
  # Every method that sends a request accepts symbol or string keys and never modifies the
  # caller's hash. It can raise {ApiError} for a JSON-RPC error in the answer, {HttpError} for an
  # HTTP status other than 200, or {TransportError} when no JSON-RPC exchange took place.
  class Basic
    # Initializes a new Basic object with ZabbixApi Client
    #
    # @param client [ZabbixApi::Client]
    # @return [ZabbixApi::Basic]
    def initialize(client)
      @client = client
    end

    # The Zabbix API object name, such as `host` in `host.get`
    #
    # @raise [ApiError] unless a subclass overrides it
    def method_name
      raise ApiError.new("Can't call method_name here")
    end

    # Properties {#create} merges under each object it sends
    #
    # @return [Hash]
    def default_options
      {}
    end

    # Returns the object's plural id field name, {#key} plus `s`, such as `hostids`
    #
    # @return [String]
    def keys
      key + 's'
    end

    # Returns the object's id field name, {#method_name} plus `id`, such as `hostid`
    #
    # @return [String]
    def key
      method_name + 'id'
    end

    # The field objects are looked up by, such as `name` or `host`
    #
    # @raise [ApiError] unless a subclass overrides it
    def identify
      raise ApiError.new("Can't call identify here")
    end
  end
end
