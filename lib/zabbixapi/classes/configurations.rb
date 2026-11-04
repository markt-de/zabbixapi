class ZabbixApi
  # Wrapper for `configuration.export`, `configuration.import` and `configuration.importcompare`.
  #
  # The API has no configuration object, so every CRUD method inherited from {Basic} raises
  # {ApiError}. `get_full_data`, `get`, `get_id`, `get_or_create` and `create_or_update` raise
  # before sending anything, as the class sets no `identify`.
  class Configurations < Basic
    # The prefix of the Zabbix API methods, as in `configuration.export`
    #
    # @return [String]
    def method_name
      'configuration'
    end

    # Export configuration data using Zabbix API
    #
    # @param data [Hash]
    # @return [String, Hash] the serialized configuration: a String for format yaml, xml or json,
    #   and a Hash for format raw, which returns the unprocessed PHP array
    def export(data)
      @client.api_request(method: "#{method_name}.export", params: data)
    end

    # Import configuration data using Zabbix API
    #
    # @param data [Hash]
    # @return [Boolean] true when the import succeeded
    def import(data)
      @client.api_request(method: "#{method_name}.import", params: data)
    end

    # Compare configuration data with the current system state, without importing it
    #
    # The dry run of {#import}, taking the same format, source and rules and answering what an
    # import would change. With no rules there is nothing to compare and the result is empty. The
    # comparison covers host groups and templates; triggers and graphs are compared only for
    # imported templates and everything else counts as new, so a host, image, map or media type
    # source reports nothing at all.
    #
    # @param data [Hash] Needs format, source and rules
    # @return [Array, Hash] an empty Array when nothing would change, and otherwise the diff as a
    #   Hash, although the API reference documents an array for both cases
    def importcompare(data)
      @client.api_request(method: "#{method_name}.importcompare", params: data)
    end
  end
end
