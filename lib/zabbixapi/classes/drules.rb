class ZabbixApi
  class Drules < Basic
    # The method name used for interacting with Drules via Zabbix API
    #
    # @return [String]
    def method_name
      'drule'
    end

    # The id field name used for identifying specific Drule objects via Zabbix API
    #
    # @return [String]
    def identify
      'name'
    end

    # The default options used when creating Drule objects via Zabbix API
    #
    # @return [Hash]
    def default_options
      {
        name: nil,
        iprange: nil,
        delay: 3600,
        status: 0,
        concurrency_max: 0
      }
    end

    # Get or Create Drule object using Zabbix API
    #
    # @param data [Hash] Needs to include name to properly identify Drule via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      unless (id = get_id(name: data[:name]))
        id = create(data)
      end
      id
    end

    # Create or update Drule object using Zabbix API
    #
    # @param data [Hash] Needs to include name to properly identify Drules via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def create_or_update(data)
      druleid = get_id(name: data[:name])
      druleid ? update(data.merge(druleid: druleid)) : create(data)
    end
  end
end
