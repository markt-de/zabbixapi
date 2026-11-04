class ZabbixApi
  # Wrapper for the `hostgroup` API object.
  class HostGroups < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'hostgroup'
    end

    # The field a host group is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # The id field name, `groupid` in the API rather than the derived `hostgroupid`
    #
    # @return [String]
    def key
      'groupid'
    end
  end
end
