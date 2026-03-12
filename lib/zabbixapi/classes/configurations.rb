class ZabbixApi
  class Configurations < Basic
    # @return [Boolean]
    def array_flag
      true
    end

    # The method name used for interacting with Configurations via Zabbix API
    #
    # @return [String]
    def method_name
      'configuration'
    end

    # The id field name used for identifying specific Configuration objects via Zabbix API
    #
    # @return [String]
    def identify
      'host'
    end

    # Export configuration data using Zabbix API
    #
    # @param data [Hash]
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Hash]
    def export(data)
      @client.api_request(method: "#{method_name}.export", params: data)
    end

    # Import configuration data using Zabbix API
    #
    # @param data [Hash]
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Hash]
    def import(data)
      @client.api_request(method: "#{method_name}.import", params: data)
    end
  end
end
