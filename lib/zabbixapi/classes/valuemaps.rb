class ZabbixApi
  class ValueMaps < Basic
    # The method name used for interacting with ValueMaps via Zabbix API
    #
    # @return [String]
    def method_name
      'valuemap'
    end

    # The id field name used for identifying specific ValueMap objects via Zabbix API
    #
    # @return [String]
    def identify
      'name'
    end

    # Get or Create ValueMap object using Zabbix API
    #
    # @param data [Hash] Needs to include valuemapids [List] to properly identify ValueMaps via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      unless (id = get_id(valuemapids: data[:valuemapids]))
        id = create(data)
      end
      id
    end

    # Create or update Item object using Zabbix API
    #
    # @param data [Hash] Needs to include valuemapids to properly identify ValueMaps via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def create_or_update(data)
      valuemapid = get_id(name: data[:name])
      valuemapid ? update(data.merge(valuemapid: valuemapid)) : create(data)
    end
  end
end
