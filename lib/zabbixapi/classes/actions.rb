class ZabbixApi
  # Wrapper for the `action` API object.
  class Actions < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'action'
    end

    # The field an action is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Get full/extended Action object data from API
    #
    # Filters on the {#identify} value alone; without one, every action is returned. Each action
    # includes its `operations`, `recovery_operations`, `update_operations` and `filter`.
    #
    # @param data [Hash] the {#identify} field and its value
    # @return [Array<Hash>]
    def get_full_data(data)
      log "[DEBUG] Call get_full_data with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      @client.api_request(
        method: "#{method_name}.get",
        params: compact_params(
          filter: {
            identify.to_sym => data[identify.to_sym]
          },
          output: 'extend',
          selectOperations: 'extend',
          selectRecoveryOperations: 'extend',
          selectUpdateOperations: 'extend',
          selectFilter: 'extend'
        )
      )
    end
  end
end
