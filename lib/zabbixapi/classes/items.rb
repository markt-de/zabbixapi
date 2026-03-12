class ZabbixApi
  class Items < Basic
    # The method name used for interacting with Items via Zabbix API
    #
    # @return [String]
    def method_name
      'item'
    end

    # The id field name used for identifying specific Item objects via Zabbix API
    #
    # @return [String]
    def identify
      'name'
    end

    # The default options used when creating Item objects via Zabbix API
    #
    # @return [Hash]
    def default_options
      {
        name: nil,
        key_: nil,
        hostid: nil,
        delay: 60,
        history: 3600,
        status: 0,
        type: 7,
        snmp_oid: '',
        value_type: 3,
        units: '',
        trends: 86400,
        logtimefmt: '',
        valuemapid: 0,
        authtype: 0,
        username: '',
        password: '',
        publickey: '',
        privatekey: '',
        params: '',
        ipmi_sensor: ''
      }
    end

    # Get or Create Item object using Zabbix API
    #
    # @param data [Hash] Needs to include name and hostid to properly identify Items via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      unless (id = get_id(name: data[:name], hostid: data[:hostid]))
        id = create(data)
      end
      id
    end

    # Create or update Item object using Zabbix API
    #
    # @param data [Hash] Needs to include name and hostid to properly identify Items via Zabbix API
    # @raise [ApiError] Error returned when there is a problem with the Zabbix API call.
    # @raise [HttpError] Error raised when HTTP status from Zabbix Server response is not a 200 OK.
    # @return [Integer] Zabbix object id
    def create_or_update(data)
      itemid = get_id(name: data[:name], hostid: data[:hostid])
      itemid ? update(data.merge(itemid: itemid)) : create(data)
    end
  end
end
