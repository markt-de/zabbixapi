class ZabbixApi
  class Usermacros < Basic
    # The method name used for interacting with User macros via Zabbix API
    #
    # @return [String]
    def method_name
      'usermacro'
    end

    # The id field name used for identifying specific User macro objects via Zabbix API
    #
    # @return [String]
    def identify
      'macro'
    end

    # Get User macro object id from Zabbix API based on provided data
    #
    # @param data [Hash] Needs to include macro to properly identify user macros via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call or missing object's id field name (identify).
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def get_id(data)
      log "[DEBUG] Call get_id with parameters: #{data.inspect}"

      # symbolize keys if the user used string keys instead of symbols
      data = symbolize_keys(data) if data.key?(identify)
      # raise an error if identify name was not supplied
      name = data[identify.to_sym]
      raise ApiError.new("#{identify} not supplied in call to get_id") if name.nil?

      result = request(data, "#{method_name}.get", 'hostmacroid')

      !result.empty? && result[0].key?('hostmacroid') ? result[0]['hostmacroid'].to_i : nil
    end

    # Get Global macro object id from Zabbix API based on provided data
    #
    # @param data [Hash] Needs to include macro to properly identify global macros via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call or missing object's id field name (identify).
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def get_id_global(data)
      log "[DEBUG] Call get_id_global with parameters: #{data.inspect}"

      # symbolize keys if the user used string keys instead of symbols
      data = symbolize_keys(data) if data.key?(identify)
      # raise an error if identify name was not supplied
      name = data[identify.to_sym]
      raise ApiError.new("#{identify} not supplied in call to get_id_global") if name.nil?

      result = request(data, "#{method_name}.get", 'globalmacroid')

      !result.empty? && result[0].key?('globalmacroid') ? result[0]['globalmacroid'].to_i : nil
    end

    # Get full/extended User macro data from Zabbix API
    #
    # @param data [Hash] Should include object's id field name (identify) and id value
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Hash]
    def get_full_data(data)
      log "[DEBUG] Call get_full_data with parameters: #{data.inspect}"

      request(data, "#{method_name}.get", 'hostmacroid')
    end

    # Get full/extended Global macro data from Zabbix API
    #
    # @param data [Hash] Should include object's id field name (identify) and id value
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Hash]
    def get_full_data_global(data)
      log "[DEBUG] Call get_full_data_global with parameters: #{data.inspect}"

      request(data, "#{method_name}.get", 'globalmacroid')
    end

    # Create new User macro object using Zabbix API (with defaults)
    #
    # @param data [Hash] Needs to include hostid, macro, and value to create User macro via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The object id if a single object is created
    # @return [Boolean] True/False if multiple objects are created
    def create(data)
      request(data, "#{method_name}.create", 'hostmacroids')
    end

    # Create new Global macro object using Zabbix API (with defaults)
    #
    # @param data [Hash] Needs to include hostid, macro, and value to create Global macro via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The object id if a single object is created
    # @return [Boolean] True/False if multiple objects are created
    def create_global(data)
      request(data, "#{method_name}.createglobal", 'globalmacroids')
    end

    # Delete User macro object using Zabbix API
    #
    # @param data [Hash] Should include hostmacroid's of User macros to delete
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The object id if a single object is deleted
    # @return [Boolean] True/False if multiple objects are deleted
    def delete(data)
      data_delete = [data]
      request(data_delete, "#{method_name}.delete", 'hostmacroids')
    end

    # Delete Global macro object using Zabbix API
    #
    # @param data [Hash] Should include hostmacroid's of Global macros to delete
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The object id if a single object is deleted
    # @return [Boolean] True/False if multiple objects are deleted
    def delete_global(data)
      data_delete = [data]
      request(data_delete, "#{method_name}.deleteglobal", 'globalmacroids')
    end

    # Update User macro object using Zabbix API
    #
    # @param data [Hash] Should include object's id field name (identify), id value, and fields to update
    # @param force [Boolean] Whether to force an object update even if provided data matches Zabbix
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The object id if a single object is created
    # @return [Boolean] True/False if multiple objects are created
    def update(data)
      request(data, "#{method_name}.update", 'hostmacroids')
    end

    # Update Global macro object using Zabbix API
    #
    # @param data [Hash] Should include object's id field name (identify), id value, and fields to update
    # @param force [Boolean] Whether to force an object update even if provided data matches Zabbix
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The object id if a single object is created
    # @return [Boolean] True/False if multiple objects are created
    def update_global(data)
      request(data, "#{method_name}.updateglobal", 'globalmacroids')
    end

    # Get or Create User macro object using Zabbix API
    #
    # @param data [Hash] Needs to include macro and hostid to properly identify User macros via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      unless (id = get_id(macro: data[:macro], hostid: data[:hostid]))
        id = create(data)
      end
      id
    end

    # Get or Create Global macro object using Zabbix API
    #
    # @param data [Hash] Needs to include macro and hostid to properly identify Global macros via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def get_or_create_global(data)
      log "[DEBUG] Call get_or_create_global with parameters: #{data.inspect}"

      unless (id = get_id_global(macro: data[:macro], hostid: data[:hostid]))
        id = create_global(data)
      end
      id
    end

    # Create or update User macro object using Zabbix API
    #
    # @param data [Hash] Needs to include macro and hostid to properly identify User macros via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def create_or_update(data)
      hostmacroid = get_id(macro: data[:macro], hostid: data[:hostid])
      hostmacroid ? update(data.merge(hostmacroid: hostmacroid)) : create(data)
    end

    # Create or update Global macro object using Zabbix API
    #
    # @param data [Hash] Needs to include macro and hostid to properly identify Global macros via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def create_or_update_global(data)
      globalmacroid = get_id_global(macro: data[:macro], hostid: data[:hostid])
      globalmacroid ? update_global(data.merge(globalmacroid: globalmacroid)) : create_global(data)
    end

  private

    # Custom request method to handle both User and Global macros in one
    #
    # @param data [Hash] Needs to include macro and hostid to properly identify Global macros via Zabbix API
    # @param method [String] Zabbix API method to use for the request
    # @param result_key [String] Which key to use for parsing results based on User vs Global macros
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def request(data, method, result_key)
      # Zabbix has different result formats for gets vs updates
      if method.include?('.get')
        if result_key.include?('global')
          @client.api_request(method: method, params: { globalmacro: true, filter: data })
        else
          @client.api_request(method: method, params: { filter: data })
        end
      else
        result = @client.api_request(method: method, params: data)

        result.key?(result_key) && !result[result_key].empty? ? result[result_key][0].to_i : nil
      end
    end
  end
end
