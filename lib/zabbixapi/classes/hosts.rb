class ZabbixApi
  class Hosts < Basic
    # The method name used for interacting with Hosts via Zabbix API
    #
    # @return [String]
    def method_name
      'host'
    end

    # The id field name used for identifying specific Host objects via Zabbix API
    #
    # @return [String]
    def identify
      'host'
    end

    # Dump Host object data by key from Zabbix API
    #
    # @param data [Hash] Should include desired object's key and value
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Hash]
    def dump_by_id(data)
      log "[DEBUG] Call dump_by_id with parameters: #{data.inspect}"

      @client.api_request(
        method: 'host.get',
        params: {
          filter: {
            key.to_sym => data[key.to_sym]
          },
          output: 'extend',
          selectHostGroups: 'extend'
        }
      )
    end

    # The default options used when creating Host objects via Zabbix API
    #
    # @return [Hash]
    def default_options
      {
        host: nil,
        interfaces: [],
        status: 0,
        available: 1,
        groups: []
      }
    end

    # Unlink/Remove Templates from Hosts using Zabbix API
    #
    # @param data [Hash] Should include hosts_id array and templates_id array
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Boolean]
    def unlink_templates(data)
      result = @client.api_request(
        method: 'host.massRemove',
        params: {
          hostids: data[:hosts_id],
          templates: data[:templates_id]
        }
      )
      result.empty? ? false : true
    end

    # Create or update Host object using Zabbix API
    #
    # @param data [Hash] Needs to include host to properly identify Hosts via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def create_or_update(data)
      hostid = get_id(host: data[:host])
      hostid ? update(data.merge(hostid: hostid)) : create(data)
    end
  end
end
