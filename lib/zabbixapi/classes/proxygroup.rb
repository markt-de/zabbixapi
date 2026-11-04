class ZabbixApi
  # Wrapper for the `proxygroup` API object.
  class Proxygroup < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'proxygroup'
    end

    # The field a proxy group is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # The id field name, `proxy_groupid` in the API rather than the derived `proxygroupid`
    #
    # @return [String]
    def key
      'proxy_groupid'
    end
  end
end
