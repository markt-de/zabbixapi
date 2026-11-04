class ZabbixApi
  # Wrapper for the `valuemap` API object.
  class ValueMaps < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'valuemap'
    end

    # The field a value map is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Get or Create ValueMap object using Zabbix API
    #
    # `hostid` scopes the lookup: a value map name is only unique within its host or
    # template. Without it the lookup spans every host and template: several matches raise,
    # and a single match elsewhere is returned instead of creating the one asked for.
    #
    # @param data [Hash] Needs to include name and hostid to properly identify ValueMaps via Zabbix API
    # @raise [ApiError] when data carries no name, or more than one value map matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the create result is empty
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      unless (id = get_id(name: data[:name], hostid: data[:hostid]))
        id = create(data)
      end
      id
    end

    # Create or update ValueMap object using Zabbix API
    #
    # `hostid` scopes the lookup, as in {#get_or_create}, but must not be forwarded to the
    # update: it is a *constant* property, and `valuemap.update` rejects it as an unexpected
    # parameter.
    #
    # @param data [Hash] Needs to include name and hostid to properly identify ValueMaps via Zabbix API
    # @raise [ApiError] when data carries no name, or more than one value map matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the result is empty
    def create_or_update(data)
      data = symbolize_keys(data)
      valuemapid = get_id(name: data[:name], hostid: data[:hostid])

      valuemapid ? update(data.reject { |field, _| field == :hostid }.merge(valuemapid: valuemapid)) : create(data)
    end
  end
end
