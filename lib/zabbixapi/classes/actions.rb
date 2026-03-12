class ZabbixApi
  class Actions < Basic
    # The method name used for interacting with Actions via Zabbix API
    #
    # @return [String]
    def method_name
      'action'
    end

    # The id field name used for identifying specific Action objects via Zabbix API
    #
    # @return [String]
    def identify
      'name'
    end

    # Get full/extended Action object data from API
    #
    # @param data [Hash] Should include object's id field name (identify) and id value
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Hash]
    def get_full_data(data)
      log "[DEBUG] Call get_full_data with parameters: #{data.inspect}"

      @client.api_request(
        method: "#{method_name}.get",
        params: {
          filter: {
            identify.to_sym => data[identify.to_sym]
          },
          output: 'extend',
          selectOperations: 'extend',
          selectRecoveryOperations: 'extend',
          selectUpdateOperations: 'extend',
          selectFilter: 'extend'
        }
      )
    end
  end
end
