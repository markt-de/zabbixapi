class ZabbixApi
  # Wrapper for the `templategroup` API object.
  class TemplateGroups < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'templategroup'
    end

    # The field a template group is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # The id field name, `groupid` in the API rather than the derived `templategroupid`
    #
    # @return [String]
    def key
      'groupid'
    end
  end
end
