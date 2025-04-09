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

    # Update Zabbix object using API
    #
    # @param data [Hash] Should include object's id field name (identify) and id value
    # @param force [Boolean] Whether to force an object update even if provided data matches Zabbix
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The object id if a single object is created
    # @return [Boolean] True/False if multiple objects are created
    def update(data, force = false)
      log "[DEBUG] Call update with parameters: #{data.inspect}"

      dump = {}
      dump_by_id(key.to_sym => data[key.to_sym]).each do |item|
        dump = symbolize_keys(item) if item[key].to_i == data[key.to_sym].to_i
      end
       # Convert 'hostgroups' to 'groups' if 'hostgroups' is present in dump
      # This is due to host.get returning existing data as the hostgroups key
      # but we have to update as the groups key
      if dump[:hostgroups]
        dump[:groups] = dump.delete(:hostgroups).map { |g| { groupid: g[:groupid].to_i } }
      end
      # Normalsation setps
      # 1. Only compare the fields in `data`, since we only care if *those* differ
      dump = dump.select { |k, _| data.key?(k) }
      # 2. Ensure groups are ordered correctly
      if dump[:groups]
        dump[:groups] = dump[:groups].map { |g| { groupid: g[:groupid].to_i } }.sort_by { |g| g[:groupid] }
      end
      log "[DEBUG] dump is: #{dump}"

      if data[:groups]
        data[:groups] = data[:groups].map { |g| { groupid: g["groupid"].to_i } }.sort_by { |g| g[:groupid] }
      end
      log "[DEBUG] data is: #{data}"

      if hash_equals?(dump, data) && !force
        log "[DEBUG] Equal keys #{dump} and #{data}, skip update"
        data[key.to_sym].to_i
      else
        data_update = [data]
        result = @client.api_request(method: "#{method_name}.update", params: data_update)
        parse_keys result
      end
    end
  end
end
