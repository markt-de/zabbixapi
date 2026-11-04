class ZabbixApi
  # Wrapper for the `item` API object.
  class Items < Basic
    # Item types for which `delay` must be 0
    #
    # Zabbix trapper (2), SNMP trap (17) and dependent (18) items are never polled, so
    # item.create and item.update refuse any other value with
    # `Invalid parameter "/1/delay": value must be 0.` The item reference does not document this.
    ZERO_DELAY_TYPES = [2, 17, 18].freeze

    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'item'
    end

    # The field an item is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Properties {Basic#create} merges under each item it sends
    #
    # @return [Hash]
    def default_options
      {
        name: nil,
        key_: nil,
        hostid: nil,
        delay: '60',
        status: 0,
        type: 7,
        snmp_oid: '',
        value_type: 3,
        units: '',
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

    # Create Item object using Zabbix API
    #
    # Corrects only this class's own `delay` default, and only for the three item types the
    # server requires 0 for. A `delay` the caller passed is forwarded untouched, even one the
    # server refuses, so the caller's mistake surfaces.
    #
    # A bulk create corrects each object in turn, so N objects in one call behave exactly as N
    # single calls would.
    #
    # @param data [Hash, Array<Hash>] one item, or several for a bulk create
    # @return [Integer, Array<Integer>, nil] Zabbix object id, an Array of ids for a bulk create,
    #   or nil when the result is empty
    def create(data)
      data = symbolize_keys(data)
      bulk = data.is_a?(Array)
      corrected = (bulk ? data : [data]).map do |object|
        type = object[:type] || default_options[:type]
        next object unless ZERO_DELAY_TYPES.include?(type.to_i)
        next object if object.key?(:delay)

        merge_params(object, delay: 0)
      end
      super(bulk ? corrected : corrected.first)
    end

    # Get or Create Item object using Zabbix API
    #
    # @param data [Hash] Needs to include name and hostid, the fields the lookup filters on
    # @raise [ApiError] when data carries no name, or more than one item matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the create result is empty
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      unless (id = get_id(name: data[:name], hostid: data[:hostid]))
        id = create(data)
      end
      id
    end

    # Create or update Item object using Zabbix API
    #
    # `hostid` scopes the lookup to one host, where an item name can repeat under another key,
    # and must not be forwarded to the update: `item.update` rejects it as an unexpected
    # parameter, and an item cannot be moved to another host anyway.
    #
    # @param data [Hash] Needs to include name and hostid, the fields the lookup filters on
    # @raise [ApiError] when data carries no name, or more than one item matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the result is empty
    def create_or_update(data)
      data = symbolize_keys(data)
      itemid = get_id(name: data[:name], hostid: data[:hostid])

      itemid ? update(data.reject { |field, _| field == :hostid }.merge(itemid: itemid)) : create(data)
    end
  end
end
