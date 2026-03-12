class ZabbixApi
  class Triggers < Basic
    # The method name used for interacting with Triggers via Zabbix API
    #
    # @return [String]
    def method_name
      'trigger'
    end

    # The id field name used for identifying specific Trigger objects via Zabbix API
    #
    # @return [String]
    def identify
      'description'
    end

    # Dump Trigger object data by key from Zabbix API
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
          filter: {
            key.to_sym => data[key.to_sym]
          },
          output: 'extend',
          select_items: 'extend',
          select_functions: 'extend'
        }
      )
    end

    # Safely update Trigger object using Zabbix API by deleting and replacing trigger
    #
    # @param data [Hash] Needs to include description and hostid to properly identify Triggers via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def safe_update(data)
      log "[DEBUG] Call safe_update with parameters: #{data.inspect}"

      dump = {}
      item_id = data[key.to_sym].to_i
      dump_by_id(key.to_sym => data[key.to_sym]).each do |item|
        dump = symbolize_keys(item) if item[key].to_i == data[key.to_sym].to_i
      end

      expression = dump[:items][0][:key_] + '.' + dump[:functions][0][:function] + '(' + dump[:functions][0][:parameter] + ')'
      dump[:expression] = dump[:expression].gsub(/\{(\d*)\}/, "{#{expression}}") # TODO: ugly regexp
      dump.delete(:functions)
      dump.delete(:items)

      old_expression = data[:expression]
      data[:expression] = data[:expression].gsub(/\{.*\:/, '{') # TODO: ugly regexp
      data.delete(:templateid)

      log "[DEBUG] expression: #{dump[:expression]}\n data: #{data[:expression]}"

      if hash_equals?(dump, data)
        log "[DEBUG] Equal keys #{dump} and #{data}, skip safe_update"
        item_id
      else
        data[:expression] = old_expression
        # disable old trigger
        log '[DEBUG] disable :' + @client.api_request(method: "#{method_name}.update", params: [{ triggerid: data[:triggerid], status: '1' }]).inspect
        # create new trigger
        data.delete(:triggerid)
        create(data)
      end
    end

    # Get or Create Trigger object using Zabbix API
    #
    # @param data [Hash] Needs to include description and hostid to properly identify Triggers via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      unless (id = get_id(description: data[:description], hostid: data[:hostid]))
        id = create(data)
      end
      id
    end

    # Create or update Trigger object using Zabbix API
    #
    # @param data [Hash] Needs to include description and hostid to properly identify Triggers via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def create_or_update(data)
      triggerid = get_id(description: data[:description], hostid: data[:hostid])

      triggerid ? update(data.merge(triggerid: triggerid)) : create(data)
    end
  end
end
