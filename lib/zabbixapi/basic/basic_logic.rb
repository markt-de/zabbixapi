class ZabbixApi
  class Basic
    # Create new Zabbix object using API (with defaults)
    #
    # Each object goes out with {#default_options} merged under it by {#merge_defaults}.
    #
    # @param data [Hash, Array<Hash>] one object, or several for a bulk create
    # @return [Integer, Array<Integer>, nil] The id of the created object, an Array of ids for a
    #   bulk create, or nil when the result is empty
    def create(data)
      log "[DEBUG] Call create with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      bulk = data.is_a?(Array)
      objects = bulk ? data : [data]
      data_create = default_options.empty? ? objects : objects.map { |object| merge_defaults(object) }
      result = @client.api_request(method: "#{method_name}.create", params: data_create)
      parse_keys(result, bulk)
    end

    # Delete Zabbix object using API
    #
    # @param data [Integer, String, Array] the object id, or an Array of ids for a bulk delete
    # @return [Integer, Array<Integer>, nil] The id of the deleted object, an Array of ids for a
    #   bulk delete, or nil when the result is empty
    def delete(data)
      log "[DEBUG] Call delete with parameters: #{data.inspect}"

      bulk = data.is_a?(Array)
      data_delete = bulk ? data : [data]
      result = @client.api_request(method: "#{method_name}.delete", params: data_delete)
      parse_keys(result, bulk)
    end

    # Create or update Zabbix object using API
    #
    # Looks the object up by its {#identify} value, then calls {#update} when it exists and
    # {#create} when it does not.
    #
    # @param data [Hash] the object, including its {#identify} field
    # @raise [ApiError] when data carries no {#identify} value, or more than one object matches it
    # @return [Integer, nil] The id of the created or updated object, or nil when the result is empty
    def create_or_update(data)
      log "[DEBUG] Call create_or_update with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      id = get_id(identify.to_sym => data[identify.to_sym])
      id ? update(data.merge(key.to_sym => id.to_s)) : create(data)
    end

    # Update Zabbix object using API
    #
    # Reads the object first and sends no update when it already holds the given values; see
    # {#skip_update?}.
    #
    # @param data [Hash] the fields to set, with the object's id under {#key}
    # @param force [Boolean] Whether to force an object update even if provided data matches Zabbix
    # @raise [ApiError] when data carries no id
    # @return [Integer, nil] The id of the updated object, also when the update was skipped, or nil when the result is empty
    def update(data, force = false)
      log "[DEBUG] Call update with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      dump = {}
      dump_by_id(key.to_sym => data[key.to_sym]).each do |item|
        dump = symbolize_keys(item) if item[key].to_i == data[key.to_sym].to_i
      end
      if skip_update?(dump, data) && !force
        log "[DEBUG] Equal keys #{dump} and #{data}, skip update"
        data[key.to_sym].to_i
      else
        data_update = [data]
        result = @client.api_request(method: "#{method_name}.update", params: data_update)
        parse_keys result
      end
    end

    # Get full/extended Zabbix object data from API
    #
    # Filters on the {#identify} value alone; without one, every object is returned.
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
          output: 'extend'
        )
      )
    end

    # Get raw Zabbix object data from API
    #
    # @param data [Hash] the get parameters, sent unchanged
    # @return [Array<Hash>, String] the matching objects, or the count when `countOutput` is set
    def get_raw(data)
      log "[DEBUG] Call get_raw with parameters: #{data.inspect}"

      @client.api_request(
        method: "#{method_name}.get",
        params: data
      )
    end

    # Dump Zabbix object data by key from API
    #
    # @param data [Hash] the object's id under {#key}
    # @raise [ApiError] when data carries no id
    # @return [Array<Hash>]
    def dump_by_id(data)
      log "[DEBUG] Call dump_by_id with parameters: #{data.inspect}"

      id = require_id!(data)

      @client.api_request(
        method: "#{method_name}.get",
        params: {
          filter: {
            key.to_sym => id
          },
          output: 'extend'
        }
      )
    end

    # Get the id of every object, keyed by its {#identify} value
    #
    # Where that value is not unique, a later row overwrites an earlier one; a scope such as
    # `hostid: 12` narrows the request.
    #
    # @param scope [Hash] optional filter properties, symbol or string keys
    # @return [Hash{String => Integer}] each object's `identify` value mapped to its id
    def all(scope = {})
      result = {}
      @client.api_request(
        method: "#{method_name}.get",
        params: compact_params(
          filter: symbolize_keys(scope),
          output: 'extend'
        )
      ).each do |item|
        result[item[identify]] = item[key].to_i
      end
      result
    end

    # Get Zabbix object id from API based on provided data
    #
    # The whole hash becomes the filter, so any scoping property narrows the lookup.
    #
    # @param data [Hash] the {#identify} field and its value, plus any scoping properties
    # @raise [ApiError] when data carries no {#identify} value, or more than one object matches
    # @return [Integer, nil] Zabbix object id, or nil when nothing matched
    def get_id(data)
      log "[DEBUG] Call get_id with parameters: #{data.inspect}"
      # symbolize keys if the user used string keys instead of symbols
      data = symbolize_keys(data) if data.key?(identify)
      name = data[identify.to_sym]
      raise ApiError.new("#{identify} not supplied in call to get_id") if name.nil?

      result = @client.api_request(
        method: "#{method_name}.get",
        params: compact_params(
          filter: data,
          output: [key, identify]
        )
      )
      one_id!(result.select { |item| item[identify] == data[identify.to_sym] }, key, 'get_id')
    end

    # Get or Create Zabbix object using API
    #
    # Looks the object up by its {#identify} value and creates it only when none exists; an
    # existing object is left unchanged.
    #
    # @param data [Hash] the object, including its {#identify} field
    # @raise [ApiError] when data carries no {#identify} value, or more than one object matches it
    # @return [Integer, nil] Zabbix object id, or nil when the create result is empty
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      unless (id = get_id(identify.to_sym => data[identify.to_sym]))
        id = create(data)
      end
      id
    end
  end
end
