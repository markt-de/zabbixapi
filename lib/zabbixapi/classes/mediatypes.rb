class ZabbixApi
  # Wrapper for the `mediatype` API object.
  class Mediatypes < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'mediatype'
    end

    # The field a media type is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Update MediaType object using API
    #
    # Unlike other resources this accepts a payload without the id, looking it up from `name`,
    # and otherwise behaves as {Basic#update}. Takes one media type; only create and delete
    # accept an Array.
    #
    # @param data [Hash] Should include name, or the mediatypeid directly
    # @param force [Boolean] Whether to force an object update even if provided data matches Zabbix
    # @raise [ApiError] when data carries neither id nor name, or the name matches no media type
    #   or more than one
    # @return [Integer, nil] The id of the updated media type, also when the update was skipped, or nil when the result is empty
    def update(data, force = false)
      data = symbolize_keys(data)

      if data[key.to_sym].nil?
        id = get_id(data)
        # Basic#update would report the id missing; the problem is the unmatched name
        raise ApiError.new("no #{method_name} found with #{identify} #{data[identify.to_sym].inspect}") if id.nil?

        data[key.to_sym] = id
        log "[DEBUG] Enriched data with id: #{data.inspect}"
      end

      super(data, force)
    end

    # Get MediaType object id from API based on provided data
    #
    # Filters on the name alone, unlike {Basic#get_id}, so {#update} can pass its whole payload.
    #
    # @param data [Hash] the {#identify} field and its value; other fields are ignored
    # @raise [ApiError] when data carries no {#identify} value, or more than one media type matches
    # @return [Integer, nil] Zabbix object id, or nil when nothing matched
    def get_id(data)
      log "[DEBUG] Call get_id with parameters: #{data.inspect}"
      # symbolize keys if the user used string keys instead of symbols
      data = symbolize_keys(data) if data.key?(identify)
      name = data[identify.to_sym]
      raise ApiError.new("#{identify} not supplied in call to get_id, #{data} (#{method_name})") if name.nil?

      result = @client.api_request(
        method: "#{method_name}.get",
        params: {
          filter: { name: name },
          output: [key, identify]
        }
      )
      one_id!(result.select { |item| item[identify] == data[identify.to_sym] }, key, 'get_id')
    end
  end
end
