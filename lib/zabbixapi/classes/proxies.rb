class ZabbixApi
  class Proxies < Basic
    # The method name used for interacting with Proxies via Zabbix API
    #
    # @return [String]
    def method_name
      'proxy'
    end

    # The id field name used for identifying specific Proxy objects via Zabbix API
    #
    # @return [String]
    def identify
      'name'
    end

    # Delete Proxy object using Zabbix API
    #
    # @param data [Array] Should include array of proxyid's
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The Proxy object id that was deleted
    def delete(data)
      result = @client.api_request(method: "#{method_name}.delete", params: data)
      result.empty? ? nil : result['proxyids'][0].to_i
    end
  end
end
