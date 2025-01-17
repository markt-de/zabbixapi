class ZabbixApi
  class Proxygroup < Basic
    # The method name used for interacting with Proxygroup via Zabbix API
    #
    # @return [String]
    def method_name
      'proxygroup'
    end

    # The id field name used for identifying specific Proxygroup objects via Zabbix API
    #
    # @return [String]
    def identify
      'name'
    end

    # The key field name used for proxygroup objects via Zabbix API
    #
    # @return [String]
    def key
      'proxy_groupid'
    end

    # Delete Proxygroup object using Zabbix API
    #
    # @param data [Array] Should include array of Proxygroupid's
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The Proxygroup object id that was deleted
    def delete(data)
      result = @client.api_request(method: 'proxygroup.delete', params: data)
      result.empty? ? nil : result['proxyids'][0].to_i
    end

    # Check if a Proxygroup object is readable using Zabbix API
    #
    # @param data [Array] Should include array of Proxygroupid's
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Boolean] Returns true if the given Proxygroupgroup are readable
    def isreadable(data)
      @client.api_request(method: 'proxygroup.isreadable', params: data)
    end

    # Check if a Proxygroup object is writable using Zabbix API
    #
    # @param data [Array] Should include array of Proxygroupid's
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Boolean] Returns true if the given Proxygroup are writable
    def iswritable(data)
      @client.api_request(method: 'proxygroup.iswritable', params: data)
    end
  end
end
