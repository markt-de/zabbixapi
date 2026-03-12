class ZabbixApi
  class Roles < Basic
    # The method name used for interacting with Role via Zabbix API
    #
    # @return [String]
    def method_name
      'role'
    end

    # The id field name used for identifying specific Role objects via Zabbix API
    #
    # @return [String]
    def identify
      'name'
    end

    # Set permissions for usergroup using Zabbix API
    #
    # @param data [Hash] Needs to include usrgrpids and hostgroupids along with permissions to set
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id (usergroup)
    def rules(data)
      rules = data[:rules] || 2
      result = @client.api_request(
        method: "#{method_name}.update",
        params: {
          roleid: data[:roleid],
          rules: data[:hostgroupids].map { |t| { permission: permission, id: t } }
        }
      )
      result ? result['usrgrpids'][0].to_i : nil
    end

    # Add users to usergroup using Zabbix API
    #
    # @deprecated Zabbix has removed massAdd in favor of update.
    # @param data [Hash] Needs to include userids and usrgrpids to mass add users to groups
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id (usergroup)
    def add_user(data)
      update_users(data)
    end

    # Dump Role object data by key from Zabbix API
    #
    # @param data [Hash] Should include desired object's key and value
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Hash]
    def dump_by_id(data)
      log "[DEBUG] Call dump_by_id with parameters: #{data.inspect}"

      @client.api_request(
        method: "#{method_name}.get",
        params: {
          output: 'extend',
          selectRules: 'extend',
          roleids: data[:id]
        }
      )
    end

    # Get Role ids by Role Name from Zabbix API
    #
    # @param data [Hash] Should include host value to query for matching graphs
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Array] Returns array of Graph ids
    def get_ids_by_name(data)
      result = @client.api_request(
        method: "#{method_name}.get",
        params: {
          filter: {
            name: data[:name]
          },
          output: 'extend'
        }
      )

      result.map do |rule|
        rule['roleid']
      end.compact
    end

    # Update users in Userroles using Zabbix API
    #
    # @param data [Hash] Needs to include userids and usrgrpids to mass update users in groups
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id (usergroup)
    def update_users(data)
      user_groups = data[:usrgrpids].map do |t|
        {
          usrgrpid: t,
          userids: data[:userids],
        }
      end
      result = @client.api_request(
        method: 'usergroup.update',
        params: user_groups,
      )
      result ? result['usrgrpids'][0].to_i : nil
    end
  end
end
