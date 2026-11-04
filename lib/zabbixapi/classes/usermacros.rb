class ZabbixApi
  # Wrapper for the `usermacro` API object: host macros, and global macros through the `*_global` methods.
  class Usermacros < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'usermacro'
    end

    # The field a macro is looked up by
    #
    # @return [String]
    def identify
      'macro'
    end

    # The id field name, `hostmacroid` in the API rather than the derived `usermacroid`
    #
    # The methods inherited from {Basic} therefore work on host macros; the `*_global` methods
    # name `globalmacroid` themselves.
    #
    # @return [String]
    def key
      'hostmacroid'
    end

    # Get User macro object id from Zabbix API based on provided data
    #
    # The whole hash becomes the filter; a macro name is only unique per host, so `hostid`
    # scopes the lookup to one host.
    #
    # @param data [Hash] the macro, plus any scoping properties such as hostid
    # @raise [ApiError] when data carries no macro, or more than one macro matches
    # @return [Integer, nil] Zabbix object id, or nil when nothing matched
    def get_id(data)
      log "[DEBUG] Call get_id with parameters: #{data.inspect}"

      # symbolize keys if the user used string keys instead of symbols
      data = symbolize_keys(data) if data.key?(identify)
      name = data[identify.to_sym]
      raise ApiError.new("#{identify} not supplied in call to get_id") if name.nil?

      result = request(data, "#{method_name}.get", 'hostmacroid')

      one_id!(result, 'hostmacroid', 'get_id')
    end

    # Get Global macro object id from Zabbix API based on provided data
    #
    # The server's filter ignores a `hostid` here rather than refusing it.
    #
    # @param data [Hash] Needs to include macro to properly identify global macros via Zabbix API
    # @raise [ApiError] when data carries no macro, or more than one global macro matches
    # @return [Integer, nil] Zabbix object id, or nil when nothing matched
    def get_id_global(data)
      log "[DEBUG] Call get_id_global with parameters: #{data.inspect}"

      # symbolize keys if the user used string keys instead of symbols
      data = symbolize_keys(data) if data.key?(identify)
      name = data[identify.to_sym]
      raise ApiError.new("#{identify} not supplied in call to get_id_global") if name.nil?

      result = request(data, "#{method_name}.get", 'globalmacroid')

      one_id!(result, 'globalmacroid', 'get_id_global')
    end

    # Get full/extended User macro data from Zabbix API
    #
    # Filters on every property given, unlike {Basic#get_full_data}; without any, every host
    # macro is returned.
    #
    # @param data [Hash] filter properties, such as macro and hostid
    # @return [Array<Hash>]
    def get_full_data(data)
      log "[DEBUG] Call get_full_data with parameters: #{data.inspect}"

      request(data, "#{method_name}.get", 'hostmacroid')
    end

    # Get full/extended Global macro data from Zabbix API
    #
    # Filters on every property given; without any, every global macro is returned.
    #
    # @param data [Hash] filter properties, such as macro
    # @return [Array<Hash>]
    def get_full_data_global(data)
      log "[DEBUG] Call get_full_data_global with parameters: #{data.inspect}"

      request(data, "#{method_name}.get", 'globalmacroid')
    end

    # Get every global macro as a macro-to-id Hash, the global twin of Basic#all
    #
    # `key` is `hostmacroid`, so this names `globalmacroid` itself, as the other *_global methods
    # do. A scope narrows the request, as in {Basic#all}.
    #
    # @param scope [Hash] optional filter properties, symbol or string keys
    # @return [Hash{String => Integer}] each global macro mapped to its globalmacroid
    def all_global(scope = {})
      result = {}
      @client.api_request(
        method: "#{method_name}.get",
        params: compact_params(
          globalmacro: true,
          filter: symbolize_keys(scope),
          output: 'extend'
        )
      ).each do |item|
        result[item[identify]] = item['globalmacroid'].to_i
      end
      result
    end

    # Create new User macro object using Zabbix API
    #
    # @param data [Hash, Array<Hash>] one macro, or several; each needs hostid, macro and value
    # @return [Integer, Array<Integer>, nil] The id of the created macro, an Array of ids for a
    #   bulk create, or nil when the result is empty
    def create(data)
      request(data, "#{method_name}.create", 'hostmacroids', data.is_a?(Array))
    end

    # Create new Global macro object using Zabbix API
    #
    # @param data [Hash, Array<Hash>] one macro, or several; each needs macro and value, no hostid
    # @return [Integer, Array<Integer>, nil] The id of the created global macro, an Array of ids
    #   for a bulk create, or nil when the result is empty
    def create_global(data)
      request(data, "#{method_name}.createglobal", 'globalmacroids', data.is_a?(Array))
    end

    # Delete User macro object using Zabbix API
    #
    # @param data [Integer, String, Array] the hostmacroid, or an Array of them for a bulk delete
    # @return [Integer, Array<Integer>, nil] The id of the deleted macro, an Array of ids for a
    #   bulk delete, or nil when the result is empty
    def delete(data)
      bulk = data.is_a?(Array)
      request(bulk ? data : [data], "#{method_name}.delete", 'hostmacroids', bulk)
    end

    # Delete Global macro object using Zabbix API
    #
    # @param data [Integer, String, Array] the globalmacroid, or an Array for a bulk delete
    # @return [Integer, Array<Integer>, nil] The id of the deleted global macro, an Array of ids
    #   for a bulk delete, or nil when the result is empty
    def delete_global(data)
      bulk = data.is_a?(Array)
      request(bulk ? data : [data], "#{method_name}.deleteglobal", 'globalmacroids', bulk)
    end

    # Update User macro object using Zabbix API
    #
    # Unlike {Basic#update} this takes no `force` argument and never compares against the
    # stored object: the request is always issued, so there is nothing to force. Takes one
    # macro; only {#create} and {#delete} accept an Array.
    #
    # `hostid` must not be included - it is a *constant* property and `usermacro.update`
    # rejects it as an unexpected parameter.
    #
    # @param data [Hash] Should include hostmacroid and the fields to update
    # @raise [ApiError] when hostmacroid is not supplied
    # @return [Integer, nil] The id of the updated macro, or nil when the result is empty
    def update(data)
      require_field!(data, 'hostmacroid', 'update')
      request(data, "#{method_name}.update", 'hostmacroids')
    end

    # Update Global macro object using Zabbix API
    #
    # As with {#update}, there is no `force` argument and the request is always issued.
    # `hostid` is not a global macro property and `usermacro.updateglobal` rejects it. Takes one
    # macro; only {#create_global} and {#delete_global} accept an Array.
    #
    # @param data [Hash] Should include globalmacroid and the fields to update
    # @raise [ApiError] when globalmacroid is not supplied
    # @return [Integer, nil] The id of the updated global macro, or nil when the result is empty
    def update_global(data)
      require_field!(data, 'globalmacroid', 'update_global')
      request(data, "#{method_name}.updateglobal", 'globalmacroids')
    end

    # Get or Create User macro object using Zabbix API
    #
    # @param data [Hash] Needs to include macro and hostid to properly identify User macros via Zabbix API
    # @raise [ApiError] when data carries no macro, or more than one macro matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the create result is empty
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      unless (id = get_id(macro: data[:macro], hostid: data[:hostid]))
        id = create(data)
      end
      id
    end

    # Get or Create Global macro object using Zabbix API
    #
    # A `hostid` is dropped if given: global macros have no host, and `usermacro.createglobal`
    # rejects it.
    #
    # @param data [Hash] Needs to include macro to properly identify Global macros via Zabbix API
    # @raise [ApiError] when data carries no macro, or more than one global macro matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the create result is empty
    def get_or_create_global(data)
      log "[DEBUG] Call get_or_create_global with parameters: #{data.inspect}"

      data = symbolize_keys(data).reject { |field, _| field == :hostid }
      unless (id = get_id_global(macro: data[:macro]))
        id = create_global(data)
      end
      id
    end

    # Create or update User macro object using Zabbix API
    #
    # `hostid` scopes the lookup - a macro name is only unique within its host - but must not
    # be forwarded to the update: it is a *constant* property and `usermacro.update` rejects
    # it as an unexpected parameter.
    #
    # @param data [Hash] Needs to include macro and hostid to properly identify User macros via Zabbix API
    # @raise [ApiError] when data carries no macro, or more than one macro matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the result is empty
    def create_or_update(data)
      data = symbolize_keys(data)
      hostmacroid = get_id(macro: data[:macro], hostid: data[:hostid])

      hostmacroid ? update(data.reject { |field, _| field == :hostid }.merge(hostmacroid: hostmacroid)) : create(data)
    end

    # Create or update Global macro object using Zabbix API
    #
    # As in {#get_or_create_global}, a `hostid` is dropped: it has no meaning for a global
    # macro and `usermacro.updateglobal` rejects it.
    #
    # @param data [Hash] Needs to include macro to properly identify Global macros via Zabbix API
    # @raise [ApiError] when data carries no macro, or more than one global macro matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the result is empty
    def create_or_update_global(data)
      data = symbolize_keys(data).reject { |field, _| field == :hostid }
      globalmacroid = get_id_global(macro: data[:macro])

      globalmacroid ? update_global(data.merge(globalmacroid: globalmacroid)) : create_global(data)
    end

  private

    # Custom request method to handle both User and Global macros in one
    #
    # @param data [Hash, Array] the filter for a `.get`, otherwise the request's params as sent
    # @param method [String] Zabbix API method to use for the request
    # @param result_key [String] the key a write's result carries its ids under; for a `.get`,
    #   one containing `global` selects global macros
    # @param bulk [Boolean] whether the caller sent an Array, so every id is returned rather than
    #   the first, as in {Basic#parse_keys}
    # @return [Array<Hash>] the matching macros, for a `.get` request
    # @return [Integer, Array<Integer>, nil] the object id, every id when bulk, or nil when empty
    def request(data, method, result_key, bulk = false)
      if method.include?('.get')
        params = result_key.include?('global') ? { globalmacro: true, filter: data } : { filter: data }
        @client.api_request(method: method, params: compact_params(params))
      else
        result = @client.api_request(method: method, params: data)
        return nil unless result.key?(result_key) && !result[result_key].empty?

        bulk ? result[result_key].map(&:to_i) : result[result_key][0].to_i
      end
    end
  end
end
