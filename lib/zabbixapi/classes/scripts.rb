class ZabbixApi
  # Wrapper for the `script` API object.
  class Scripts < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'script'
    end

    # The field a script is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Run a script on a host or against an event using the Zabbix API
    #
    # `scriptid` is always required, plus either `hostid` or `eventid` - the two are
    # alternatives, and which one is valid depends on the script's `scope` (2 is a manual host
    # action, 4 a manual event action). `manualinput` supplies the value of the MANUALINPUT
    # macro for scripts that ask for one.
    #
    # Only the parameters actually supplied are sent. A failing script raises {ApiError} with the
    # script's own output as its failure text.
    #
    # @example Run a script on a host
    #   execute(scriptid: 12, hostid: 32)
    # @example Run a script against an event, answering its manual input prompt
    #   execute(scriptid: 12, eventid: 39, manualinput: 'yes')
    #
    # @param data [Hash] Needs scriptid, plus hostid or eventid; optionally manualinput
    # @return [Hash] `response` ('success'), `value` (script output) and `debug`
    def execute(data)
      data = symbolize_keys(data)
      @client.api_request(
        method: "#{method_name}.execute",
        params: compact_params(
          scriptid: data[:scriptid],
          hostid: data[:hostid],
          eventid: data[:eventid],
          manualinput: data[:manualinput]
        )
      )
    end

    # Retrieve the scripts available for the given hosts using the Zabbix API
    #
    # The Zabbix method is `script.getscriptsbyhosts`, plural. Pass an object - or an array of
    # objects - with `hostid` (required), and optionally `scriptid` and `manualinput`; a bare
    # array of host ids is refused with "an array is expected".
    #
    # The data is passed through unchanged, so any documented parameter combination works.
    #
    # @example
    #   getscriptsbyhost(hostid: 10721)
    #
    # @param data [Hash, Array<Hash>] Needs hostid; optionally scriptid and manualinput
    # @return [Hash] Host ids as keys, arrays of available scripts as values
    def getscriptsbyhost(data)
      @client.api_request(method: "#{method_name}.getscriptsbyhosts", params: data)
    end

    # Retrieve the scripts available for the given events using the Zabbix API
    #
    # The event twin of {#getscriptsbyhost}. Pass an object - or an array of objects - with
    # `eventid`, required and unique within the array, and optionally `scriptid` and
    # `manualinput`. The data is passed through unchanged, so any documented combination works.
    #
    # The server expands macros in the confirmation text, the manual input prompt and the url,
    # and resolves the MANUALINPUT macro to `manualinput` where one is given.
    #
    # @example
    #   getscriptsbyevents(eventid: 632)
    #
    # @param data [Hash, Array<Hash>] Needs eventid; optionally scriptid and manualinput
    # @return [Hash] Event ids as keys, arrays of available scripts as values
    def getscriptsbyevents(data)
      @client.api_request(method: "#{method_name}.getscriptsbyevents", params: data)
    end
  end
end
