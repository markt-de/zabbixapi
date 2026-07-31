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

    # Mass update objects related to the given Templates using Zabbix API
    #
    # Replaces the given template groups and macros on the given templates. This manages
    # objects *belonging to* templates - it cannot link templates to hosts; use
    # {Hosts#unlink_templates} or host.massAdd for that.
    #
    # @param data [Hash] Should include templates_id array; optionally groups_id array and macros array
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Boolean]
    def mass_update(data)
      result = @client.api_request(
        method: "#{method_name}.massUpdate",
        params: mass_params(data)
      )
      result.empty? ? false : true
    end

    # Mass add objects related to the given Templates using Zabbix API
    #
    # Adds the given template groups and macros to the given templates. This manages objects
    # *belonging to* templates - it cannot link templates to hosts; use
    # {Hosts#unlink_templates} or host.massAdd for that.
    #
    # @param data [Hash] Should include templates_id array; optionally groups_id array and macros array
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Boolean]
    def mass_add(data)
      result = @client.api_request(
        method: "#{method_name}.massAdd",
        params: mass_params(data)
      )
      result.empty? ? false : true
    end

    # Mass remove objects related to the given Templates using Zabbix API
    #
    # Removes the given template groups and macros from the given templates.
    #
    # @param data [Hash] Should include templates_id array; optionally group_id array and macros array
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Boolean]
    def mass_remove(data)
      params = { templateids: data[:templates_id] }
      params[:groupids] = data[:group_id] if data[:group_id]
      params[:macros] = data[:macros] if data[:macros]

      result = @client.api_request(
        method: "#{method_name}.massRemove",
        params: params
      )
      result.empty? ? false : true
    end

  private

    # Build the shared parameter set for template.massAdd / template.massUpdate
    #
    # @param data [Hash]
    # @return [Hash]
    def mass_params(data)
      params = { templates: data[:templates_id].map { |t| { templateid: t } } }
      params[:groups] = data[:groups_id].map { |g| { groupid: g } } if data[:groups_id]
      params[:macros] = data[:macros] if data[:macros]
      params
    end
  end
end
