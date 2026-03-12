class ZabbixApi
  class Templates < Basic
    # The method name used for interacting with Templates via Zabbix API
    #
    # @return [String]
    def method_name
      'template'
    end

    # The id field name used for identifying specific Template objects via Zabbix API
    #
    # @return [String]
    def identify
      'host'
    end

    # Delete Template object using Zabbix API
    #
    # @param data [Array] Should include array of templateid's
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] The Template object id that was deleted
    def delete(data)
      result = @client.api_request(method: "#{method_name}.delete", params: [data])
      result.empty? ? nil : result['templateids'][0].to_i
    end

    # Get Template ids for Host from Zabbix API
    #
    # @param data [Hash] Should include host value to query for matching templates
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Array] Returns array of Template ids
    def get_ids_by_host(data)
      @client.api_request(method: "#{method_name}.get", params: data).map do |tmpl|
        tmpl['templateid']
      end
    end

    # Get or Create Template object using Zabbix API
    #
    # @param data [Hash] Needs to include host to properly identify Templates via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def get_or_create(data)
      unless (templateid = get_id(host: data[:host]))
        templateid = create(data)
      end
      templateid
    end

    # Mass update Templates for Hosts using Zabbix API
    #
    # @param data [Hash] Should include hosts_id array and templates_id array
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Boolean]
    def mass_update(data)
      result = @client.api_request(
        method: "#{method_name}.massUpdate",
        params: {
          templates: data[:templates_id].map { |t| { templateid: t } }
        }
      )
      result.empty? ? false : true
    end

    # Mass add Templates to Hosts using Zabbix API
    #
    # @param data [Hash] Should include hosts_id array and templates_id array
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Boolean]
    def mass_add(data)
      result = @client.api_request(
        method: "#{method_name}.massAdd",
        params: {
          templates: data[:templates_id].map { |t| { templateid: t } }
        }
      )
      result.empty? ? false : true
    end

    # Mass remove Templates to Hosts using Zabbix API
    #
    # @param data [Hash] Should include hosts_id array and templates_id array
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Boolean]
    def mass_remove(data)
      result = @client.api_request(
        method: "#{method_name}.massRemove",
        params: {
          templateids: data[:templates_id],
          groupids: data[:group_id]
        }
      )
      result.empty? ? false : true
    end
  end
end
