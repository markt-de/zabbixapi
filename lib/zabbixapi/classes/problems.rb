class ZabbixApi
  # Wrapper for the `problem` API object, read-only.
  class Problems < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'problem'
    end

    # The field a problem is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # The id field name: a problem carries its event's `eventid`, and the API has no `problemid`
    #
    # @return [String]
    def key
      'eventid'
    end

    [:create, :delete, :update, :create_or_update, :get_or_create].each do |unsupported|
      define_method(unsupported) do |*|
        raise ApiError.new("Problems##{unsupported} is not supported: the Zabbix problem API only provides problem.get")
      end
    end

    # Get full/extended Problem data from Zabbix API
    #
    # Every documented `problem.get` parameter is forwarded; `sortfield` is dropped when
    # `countOutput` is set. A caller's `filter` is merged under the `name` shortcut, so a
    # top-level `name:` wins over a `filter: { name: ... }`. `problem.get`'s filter accepts 11 of
    # the object's 17 properties and refuses any other key, where other objects ignore an unknown
    # one; its `search` takes `name` alone.
    #
    # `output` defaults to `extend` and may be overridden; the three selects may not.
    # `sortorder` defaults to `DESC`, newest first, where the API sorts ascending.
    #
    # @param data [Hash] any documented problem.get parameter, plus `name` as a filter shortcut
    # @return [Array<Hash>, String] the matching problems, or the count when `countOutput` is set
    def get_full_data(data)
      log "[DEBUG] Call get_full_data with parameters: #{data.inspect}"

      data = symbolize_keys(data)

      params = {
        filter: merge_params(data[:filter] || {}, compact_params(identify.to_sym => data[identify.to_sym])),
        eventids: data[:eventids],
        groupids: data[:groupids],
        hostids: data[:hostids],
        objectids: data[:objectids],
        source: data[:source] || 0,
        object: data[:object] || 0,
        # acknowledged, suppressed and symptom narrow the result when false as well as when true,
        # so they go out only when the caller sets them
        acknowledged: data[:acknowledged],
        action: data[:action],
        action_userids: data[:action_userids],
        suppressed: data[:suppressed],
        symptom: data[:symptom],
        severities: data[:severities],
        evaltype: data[:evaltype] || 0,
        tags: data[:tags],
        recent: data[:recent],
        eventid_from: data[:eventid_from],
        eventid_till: data[:eventid_till],
        time_from: data[:time_from],
        time_till: data[:time_till],
        sortfield: data[:sortfield] || ['eventid'],
        countOutput: data[:countOutput],
        sortorder: data[:sortorder] || 'DESC',
        output: data[:output] || 'extend',
        search: data[:search],
        searchByAny: data[:searchByAny],
        searchWildcardsEnabled: data[:searchWildcardsEnabled],
        startSearch: data[:startSearch],
        excludeSearch: data[:excludeSearch],
        editable: data[:editable],
        limit: data[:limit],
        preservekeys: data[:preservekeys],
        selectAcknowledges: 'extend',
        selectTags: 'extend',
        selectSuppressionData: 'extend'
      }

      # Zabbix 7.0 fails a countOutput request that also carries sortfield with
      # "Database error occurred."
      params.delete(:sortfield) if params[:countOutput]

      @client.api_request(method: "#{method_name}.get", params: compact_params(params))
    end

    # Get full/extended Zabbix data for Problem objects from API
    #
    # {#get_full_data} without parameters, so an Array of problem objects rather than the
    # name-to-id Hash {Basic#all} answers.
    #
    # @return [Array<Hash>] Array of matching objects
    def all
      get_full_data({})
    end
  end
end
