class ZabbixApi
  # Wrapper for the `drule` API object, a network discovery rule.
  class Drules < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'drule'
    end

    # The field a discovery rule is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Properties {Basic#create} merges under each discovery rule it sends
    #
    # `delay` is a string in the API, seconds or a time unit; the server's own default is '1h'.
    # `dchecks` is required and has no default: a create without it is refused with "Cannot save
    # discovery rule without checks."
    #
    # @return [Hash]
    def default_options
      {
        name: nil,
        iprange: nil,
        delay: '3600',
        status: 0,
        concurrency_max: 0
      }
    end
  end
end
