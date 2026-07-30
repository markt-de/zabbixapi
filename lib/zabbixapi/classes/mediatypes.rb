class ZabbixApi
  class Mediatypes < Basic
    # The method name used for interacting with MediaTypes via Zabbix API
    #
    # @return [String]
    def method_name
      'mediatype'
    end

    # The id field name used for identifying specific MediaType objects via Zabbix API
    #
    # @return [String]
    def identify
      'name'
    end

    # The default options used when creating MediaType objects via Zabbix API
    #
    # @return [Hash]
    def default_options
      {
        name: '',
        description: '',
        type: 0,
        smtp_server: '',
        smtp_helo: '',
        smtp_email: '',
        exec_path: '',
        gsm_modem: '',
        username: '',
        passwd: ''
      }
    end

    # Update MediaType object using API
    #
    # @param data [Hash] Should include object's id field name (identify) and id value
    # @param force [Boolean] Whether to force an object update even if provided data matches Zabbix
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The object id if a single object is created
    # @return [Boolean] True/False if multiple objects are created
    def update(data, force = false)
      log "[DEBUG] Call update with parameters: #{data.inspect}"
      if data[key.to_sym].nil?
        data[key.to_sym] = get_id(data)
        log "[DEBUG] Enriched data with id: #{data.inspect}"
      end
      dump = {}
      dump_by_id(key.to_sym => data[key.to_sym]).each do |item|
        dump = symbolize_keys(item) if item[key].to_i == data[key.to_sym].to_i
      end
      if hash_equals?(dump, data) && !force
        log "[DEBUG] Equal keys #{dump} and #{data}, skip update"
        data[key.to_sym].to_i
      else
        data_update = [data]
        result = @client.api_request(method: "#{method_name}.update", params: data_update)
        parse_keys result
      end
    end

    # Get MediaType object id from API based on provided data
    #
    # @param data [Hash]
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call or missing object's id field name (identify).
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def get_id(data)
      log "[DEBUG] Call get_id with parameters: #{data.inspect}"
      # symbolize keys if the user used string keys instead of symbols
      data = symbolize_keys(data) if data.key?(identify)
      # raise an error if identify name was not supplied
      name = data[identify.to_sym]
      raise ApiError.new("#{identify} not supplied in call to get_id, #{data} (#{method_name})") if name.nil?

      result = @client.api_request(
        method: "#{method_name}.get",
        params: {
          filter: { name: name },
          output: [key, identify]
        }
      )
      id = nil
      result.each { |item| id = item[key].to_i if item[identify] == data[identify.to_sym] }
      id
    end

    # Create or update MediaType object using API
    #
    # @param data [Hash] Should include object's id field name (identify) and id value
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The object id if a single object is created
    # @return [Boolean] True/False if multiple objects are created
    def create_or_update(data)
      log "[DEBUG] Call create_or_update with parameters: #{data.inspect}"

      id = get_id(identify.to_sym => data[identify.to_sym])
      id ? update(data.merge(key.to_sym => id.to_s)) : create(data)
    end
  end
end
