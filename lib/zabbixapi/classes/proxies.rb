class ZabbixApi
  # Wrapper for the `proxy` API object.
  class Proxies < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'proxy'
    end

    # The field a proxy is looked up by
    #
    # @return [String]
    def identify
      'name'
    end
  end
end
