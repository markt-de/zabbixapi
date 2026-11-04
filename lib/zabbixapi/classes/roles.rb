class ZabbixApi
  # Wrapper for the `role` API object.
  class Roles < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'role'
    end

    # The field a role is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Set the rules for a Role using the Zabbix API
    #
    # `role.update` merges the given rules into the stored ones: a rules property left out keeps
    # its value.
    #
    # @param data [Hash] Needs to include roleid and the rules structure to set
    # @return [Integer, nil] Zabbix Role id, or nil when the server returns no result
    def rules(data)
      data = symbolize_keys(data)
      result = @client.api_request(
        method: "#{method_name}.update",
        params: {
          roleid: data[:roleid],
          rules: data[:rules]
        }
      )
      result ? result['roleids'][0].to_i : nil
    end

    # Dump Role object data by key from Zabbix API
    #
    # Selects each role's `rules` as well, which {Basic#update} compares with a payload's `rules`.
    #
    # @param data [Hash] the role's id under {#key} or `id`
    # @raise [ApiError] when data carries no id
    # @return [Array<Hash>]
    def dump_by_id(data)
      log "[DEBUG] Call dump_by_id with parameters: #{data.inspect}"

      @client.api_request(
        method: "#{method_name}.get",
        params: {
          output: 'extend',
          selectRules: 'extend',
          keys.to_sym => [require_id!(data, :id)]
        }
      )
    end

    # Get Role ids by Role Name from Zabbix API
    #
    # @param data [Hash] Should include the name to query for matching roles
    # @raise [ApiError] when name is not supplied
    # @return [Array<Integer>] Returns array of Role ids
    def get_ids_by_name(data)
      result = @client.api_request(
        method: "#{method_name}.get",
        params: {
          filter: {
            name: require_field!(data, 'name', 'get_ids_by_name')
          },
          output: 'extend'
        }
      )

      result.map do |role|
        role['roleid']&.to_i
      end.compact
    end
  end
end
