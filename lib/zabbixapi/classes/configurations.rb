class ZabbixApi
  # Configuration import/export.
  #
  # There is no "configuration" object in the Zabbix API and therefore no CRUD surface: the
  # API provides only configuration.export, configuration.import and
  # configuration.importcompare. Only export and import are wrapped here, and the CRUD
  # methods inherited from Basic are not usable - identify is deliberately left unset so
  # calling them fails loudly rather than issuing a request that cannot succeed.
  class Configurations < Basic
    # The method name used for interacting with Configurations via Zabbix API
    #
    # @return [String]
    def method_name
      'configuration'
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
