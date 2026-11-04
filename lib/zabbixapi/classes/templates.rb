class ZabbixApi
  # Wrapper for the `template` API object.
  class Templates < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'template'
    end

    # The field a template is looked up by
    #
    # @return [String]
    def identify
      'host'
    end

    # Dump Template object data by id from Zabbix API
    #
    # Selects by the `templateids` parameter: `template.get` with `filter: { templateid: ... }`,
    # as {Basic#dump_by_id} sends it, matches nothing, templates being stored in the hosts table.
    #
    # @param data [Hash] the template's id under {#key}
    # @raise [ApiError] when data carries no id
    # @return [Array<Hash>]
    def dump_by_id(data)
      log "[DEBUG] Call dump_by_id with parameters: #{data.inspect}"

      @client.api_request(
        method: "#{method_name}.get",
        params: {
          keys.to_sym => [require_id!(data)],
          output: 'extend'
        }
      )
    end

    # Get Template ids for Host from Zabbix API
    #
    # Accepts either the template's `identify` value (`host: 'name'`), which is turned into a
    # filter, or a full `template.get` parameter hash that is passed through unchanged (e.g.
    # `hostids: [1]` or `filter: { host: 'name' }`). `host` is no `template.get` parameter, so
    # sent raw it would be ignored and every template returned; a nil `host` or an empty hash is
    # refused for the same reason.
    #
    # @param data [Hash] The template's host value, or template.get parameters
    # @raise [ApiError] when nothing to select on is supplied
    # @return [Array<Integer>] Returns array of Template ids
    def get_ids_by_host(data)
      data = symbolize_keys(data)
      raise ApiError.new('no parameters supplied in call to get_ids_by_host') if data.empty?

      params = data
      params = { filter: { identify.to_sym => require_field!(data, identify, 'get_ids_by_host') }, output: [key] } if data.key?(identify.to_sym)

      @client.api_request(method: "#{method_name}.get", params: params).map do |tmpl|
        tmpl[key]&.to_i
      end
    end

    # Mass update objects related to the given Templates using Zabbix API
    #
    # Replaces the given template groups and macros on the given templates, and - with
    # `templates_link_id` - the templates they are linked to. This manages objects *belonging to*
    # templates; a template is linked to a *host* with host.massAdd and unlinked with
    # {Hosts#unlink_templates}.
    #
    # `templates_clear_id` unlinks and clears, `templates_link_id` replaces the linked set. Both
    # take arrays of ids, as `templates_id` and `groups_id` do, and are mapped to the objects the
    # API wants. A key this method cannot forward raises.
    #
    # @param data [Hash] templates_id array; optionally groups_id, macros, templates_link_id,
    #   templates_clear_id
    # @raise [ApiError] when templates_id is not supplied, or on an unknown parameter
    # @return [Boolean]
    def mass_update(data)
      result = @client.api_request(
        method: "#{method_name}.massUpdate",
        params: mass_params(data, [:templates_id, :groups_id, :macros, :templates_link_id, :templates_clear_id], 'mass_update')
      )
      result.empty? ? false : true
    end

    # Mass add objects related to the given Templates using Zabbix API
    #
    # Adds the given template groups and macros to the given templates, and - with
    # `templates_link_id` - links further templates to them. This manages objects *belonging to*
    # templates; a template is linked to a *host* with host.massAdd and unlinked with
    # {Hosts#unlink_templates}.
    #
    # `template.massAdd` has no clear variant, so `templates_clear_id` is not accepted here and
    # raises like any other unknown key; {#mass_update} and {#mass_remove} take it.
    #
    # @param data [Hash] templates_id array; optionally groups_id, macros, templates_link_id
    # @raise [ApiError] when templates_id is not supplied, or on an unknown parameter
    # @return [Boolean]
    def mass_add(data)
      result = @client.api_request(
        method: "#{method_name}.massAdd",
        params: mass_params(data, [:templates_id, :groups_id, :macros, :templates_link_id], 'mass_add')
      )
      result.empty? ? false : true
    end

    # Mass remove objects related to the given Templates using Zabbix API
    #
    # Removes the given template groups and macros from the given templates, and - with
    # `templates_link_id` or `templates_clear_id` - unlinks templates from them, the second
    # clearing the inherited entities as well.
    #
    # `template.massRemove` names its link parameters `templateids_link` and `templateids_clear`
    # and takes bare ids where the other two take objects; the caller writes the same
    # `templates_link_id` and `templates_clear_id` either way.
    #
    # @param data [Hash] templates_id array; optionally groups_id, macros, templates_link_id,
    #   templates_clear_id
    # @raise [ApiError] when templates_id is not supplied, or on an unknown parameter
    # @return [Boolean]
    def mass_remove(data)
      data = reject_unknown!(symbolize_keys(data), [:templates_id, :groups_id, :macros, :templates_link_id, :templates_clear_id], 'mass_remove')
      params = { templateids: require_field!(data, 'templates_id', 'mass_remove') }
      params[:groupids] = data[:groups_id] if data[:groups_id]
      params[:macros] = data[:macros] if data[:macros]
      params[:templateids_link] = data[:templates_link_id] if data[:templates_link_id]
      params[:templateids_clear] = data[:templates_clear_id] if data[:templates_clear_id]

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
    # @param allowed [Array<Symbol>] the keys the calling method can forward
    # @param caller_name [String] method name to name in a refusal
    # @raise [ApiError] when templates_id is missing, or the payload carries a key that method
    #   cannot forward
    # @return [Hash]
    def mass_params(data, allowed, caller_name)
      data = reject_unknown!(symbolize_keys(data), allowed, caller_name)
      params = { templates: require_field!(data, 'templates_id', caller_name).map { |t| { templateid: t } } }
      params[:groups] = data[:groups_id].map { |g| { groupid: g } } if data[:groups_id]
      params[:macros] = data[:macros] if data[:macros]
      params[:templates_link] = data[:templates_link_id].map { |t| { templateid: t } } if data[:templates_link_id]
      params[:templates_clear] = data[:templates_clear_id].map { |t| { templateid: t } } if data[:templates_clear_id]
      params
    end

    # Refuse a mass_* payload carrying a key the method cannot forward
    #
    # Such a key would otherwise be dropped while the call still answers true. The accepted sets
    # differ per method because the API's do: massAdd links but cannot clear, and massRemove names
    # its link parameters templateids_* where the other two use templates_*.
    #
    # @param data [Hash] the caller's normalised payload
    # @param allowed [Array<Symbol>] the keys this method can forward
    # @param caller_name [String] method name to name in the error message
    # @raise [ApiError] when the payload carries anything else
    # @return [Hash] the payload as given
    def reject_unknown!(data, allowed, caller_name)
      unknown = data.keys - allowed
      raise ApiError.new("unknown parameter #{unknown.join(', ')} in call to #{caller_name}, which forwards #{allowed.join(', ')}") unless unknown.empty?

      data
    end
  end
end
