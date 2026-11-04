class ZabbixApi
  # Wrapper for the `maintenance` API object.
  #
  # `create` needs `name`, `active_since`, `active_till`, `timeperiods` and at least one of
  # `groups` or `hosts`, none of them defaulted here. A maintenance without a group or host is
  # refused with "At least one host group or host must be selected." rather than a
  # named-parameter error.
  #
  # The server stores `active_since` and `active_till` truncated to the minute. `groups`, `hosts`,
  # `timeperiods` and `tags` come back only with their `select*` parameter, so {Basic#update}
  # always sends a payload carrying one of them.
  class Maintenance < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'maintenance'
    end

    # The field a maintenance is looked up by
    #
    # @return [String]
    def identify
      'name'
    end
  end
end
