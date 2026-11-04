class ZabbixApi
  # Wrapper for the `host` API object.
  class Hosts < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'host'
    end

    # The field a host is looked up by
    #
    # @return [String]
    def identify
      'host'
    end

    # Dump Host object data by key from Zabbix API
    #
    # Selects each host's `hostgroups` as well, which {#update} compares with a payload's `groups`.
    #
    # @param data [Hash] the host's id under {#key}
    # @raise [ApiError] when data carries no id
    # @return [Array<Hash>]
    def dump_by_id(data)
      log "[DEBUG] Call dump_by_id with parameters: #{data.inspect}"

      @client.api_request(
        method: "#{method_name}.get",
        params: {
          filter: {
            key.to_sym => require_id!(data)
          },
          output: 'extend',
          selectHostGroups: 'extend'
        }
      )
    end

    # Properties {Basic#create} merges under each host it sends
    #
    # @return [Hash]
    def default_options
      {
        host: nil,
        interfaces: [],
        status: 0,
        groups: []
      }
    end

    # Unlink/Remove Templates from Hosts using Zabbix API
    #
    # `clear: true` unlinks *and clears*: the items, triggers, graphs and web scenarios the hosts
    # inherited go with the link. `host.massRemove` then gets the ids as `templateids_clear`
    # instead of `templateids`.
    #
    # @param data [Hash] Should include hosts_id array and templates_id array, optionally clear
    # @return [Boolean]
    def unlink_templates(data)
      data = symbolize_keys(data)
      field = data[:clear] ? :templateids_clear : :templateids
      result = @client.api_request(
        method: "#{method_name}.massRemove",
        params: {
          hostids: data[:hosts_id],
          field => data[:templates_id]
        }
      )
      result.empty? ? false : true
    end

    # Update Zabbix object using API
    #
    # Reads the host first and sends no update when it already holds the given values, `groups`
    # compared by `groupid` in any order; see {#skip_update?}. Takes one host; only create and
    # delete accept an Array.
    #
    # @param data [Hash] the fields to set, with the host's id under {#key}
    # @param force [Boolean] Whether to force an object update even if provided data matches Zabbix
    # @raise [ApiError] when data carries no id
    # @return [Integer, nil] The id of the updated host, also when the update was skipped, or nil when the result is empty
    def update(data, force = false)
      log "[DEBUG] Call update with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      dump = {}
      dump_by_id(key.to_sym => data[key.to_sym]).each do |item|
        dump = symbolize_keys(item) if item[key].to_i == data[key.to_sym].to_i
      end
      # host.get answers the groups as `hostgroups`, host.update takes them as `groups`
      dump[:groups] = dump.delete(:hostgroups).map { |g| { groupid: g[:groupid].to_i } } if dump[:hostgroups]
      # Compare only the fields the payload carries, and the groups in groupid order
      dump = dump.select { |k, _| data.key?(k) }
      dump[:groups] = dump[:groups].map { |g| { groupid: g[:groupid].to_i } }.sort_by { |g| g[:groupid] } if dump[:groups]
      log "[DEBUG] dump is: #{dump}"

      # The payload's groups take the same shape. `data` is the copy `symbolize_keys` made, so
      # either key style works and the caller's hash is never written.
      data[:groups] = data[:groups].map { |g| { groupid: g[:groupid].to_i } }.sort_by { |g| g[:groupid] } if data[:groups]
      log "[DEBUG] data is: #{data}"

      if skip_update?(dump, data) && !force
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
