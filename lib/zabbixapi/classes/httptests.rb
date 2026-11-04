class ZabbixApi
  # Wrapper for the `httptest` API object, a web scenario.
  class HttpTests < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'httptest'
    end

    # The field a web scenario is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Properties {Basic#create} merges under each web scenario it sends
    #
    # @return [Hash]
    def default_options
      {
        hostid: nil,
        name: nil,
        steps: []
      }
    end

    # Get or Create HttpTest object using Zabbix API
    #
    # @param data [Hash] Needs to include name and hostid to properly identify HttpTests via Zabbix API
    # @raise [ApiError] when data carries no name, or more than one web scenario matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the create result is empty
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      unless (id = get_id(name: data[:name], hostid: data[:hostid]))
        id = create(data)
      end
      id
    end

    # Create or update HttpTest object using Zabbix API
    #
    # `hostid` scopes the lookup, since web scenario names are only unique per host. It must
    # not be forwarded to the update: `httptest.update` rejects it as an unexpected
    # parameter.
    #
    # @param data [Hash] Needs to include name and hostid to properly identify HttpTests via Zabbix API
    # @raise [ApiError] when data carries no name, or more than one web scenario matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the result is empty
    def create_or_update(data)
      data = symbolize_keys(data)
      httptestid = get_id(name: data[:name], hostid: data[:hostid])

      httptestid ? update(data.reject { |field, _| field == :hostid }.merge(httptestid: httptestid)) : create(data)
    end
  end
end
