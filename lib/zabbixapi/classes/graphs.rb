class ZabbixApi
  # Wrapper for the `graph` API object.
  class Graphs < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'graph'
    end

    # The field a graph is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Get full/extended Graph data from Zabbix API
    #
    # Searches rather than filters on the {#identify} value, so every graph whose name contains it
    # matches; without one, every graph is returned.
    #
    # @param data [Hash] the {#identify} field and its value
    # @return [Array<Hash>]
    def get_full_data(data)
      log "[DEBUG] Call get_full_data with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      @client.api_request(
        method: "#{method_name}.get",
        params: compact_params(
          search: {
            identify.to_sym => data[identify.to_sym]
          },
          output: 'extend'
        )
      )
    end

    # Get Graph ids for Host from Zabbix API
    #
    # `data[:filter]` is not an API filter but a Ruby regular expression, matched against the
    # returned graph names.
    #
    # @param data [Hash] Should include host value to query for matching graphs
    # @raise [ApiError] when host is not supplied
    # @return [Array<Integer>] Returns array of Graph ids
    def get_ids_by_host(data)
      data = symbolize_keys(data)
      result = @client.api_request(
        method: "#{method_name}.get",
        params: {
          filter: {
            host: require_field!(data, 'host', 'get_ids_by_host')
          },
          output: 'extend'
        }
      )

      result.map do |graph|
        num  = graph['graphid']&.to_i
        name = graph['name']
        filter = data[:filter]

        num if filter.nil? || /#{filter}/ =~ name
      end.compact
    end

    # Get Graph Item object using Zabbix API
    #
    # Takes the bare graph id; a Hash is refused by the server with `Database error occurred.`
    #
    # @param data [Integer, String] The id of the graph whose items are read
    # @return [Array<Hash>]
    def get_items(data)
      @client.api_request(
        method: 'graphitem.get',
        params: {
          graphids: [data],
          output: 'extend'
        }
      )
    end

    # Get or Create Graph object using Zabbix API
    #
    # `hostid` scopes the lookup. It is not a graph property but an additional `graph.get` filter
    # property, and it resolves graphs on a template just as well as on a host. It never reaches
    # the create, which has no such parameter.
    #
    # @param data [Hash] Needs to include name and hostid to properly identify Graphs via Zabbix API
    # @raise [ApiError] when data carries no name, or more than one graph matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the create result is empty
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      unless (id = get_id(name: data[:name], hostid: data[:hostid]))
        id = create(strip_scope(data))
      end

      id
    end

    # Create or update Graph object using Zabbix API
    #
    # `hostid` scopes the lookup, for the reasons given on {#get_or_create}, and is dropped from
    # the write because `graph.create` and `graph.update` have no such parameter.
    #
    # Note this cannot rename a graph, because `name` is the lookup key: passing a new name
    # simply creates a second graph. Use {#update} with an explicit `graphid` to rename.
    #
    # @param data [Hash] Needs to include name and hostid to properly identify Graphs via Zabbix API
    # @raise [ApiError] when data carries no name, or more than one graph matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the result is empty
    def create_or_update(data)
      data = symbolize_keys(data)
      graphid = get_id(name: data[:name], hostid: data[:hostid])
      payload = strip_scope(data)

      graphid ? update(payload.merge(graphid: graphid)) : create(payload)
    end

    # Drop the fields that scope a lookup but must never reach a write
    #
    # `hostid` is not a graph parameter at all, and `templateid` is read-only: `graph.update`
    # rejects it with `Cannot update "templateid"` and `graph.create` with
    # `Cannot set "templateid"`.
    #
    # @param data [Hash]
    # @return [Hash]
    def strip_scope(data)
      data.reject { |field, _| [:hostid, :templateid].include?(field) }
    end
  end
end
