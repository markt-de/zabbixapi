class ZabbixApi
  class Scripts < Basic
    def method_name
      'script'
    end

    # The id field name used for identifying specific Screen objects via Zabbix API
    #
    # @return [String]
    def identify
      'name'
    end

    # Submits a request to the zabbix api
    # data - A Hash containing the scriptid and hostid
    #
    # Example:
    #   execute({ scriptid: '12', hostid: '32 })
    #
    # Returns nothing
    def execute(data)
      @client.api_request(
        method: "#{method_name}.execute",
        params: {
          scriptid: data[:scriptid],
          hostid: data[:hostid]
        }
      )
    end

    def getscriptsbyhost(data)
      @client.api_request(method: "#{method_name}.getscriptsbyhosts", params: data)
    end
  end
end
