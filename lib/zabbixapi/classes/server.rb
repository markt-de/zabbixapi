class ZabbixApi
  # The API version of the Zabbix server a client is connected to.
  class Server
    # @return [String]
    attr_reader :version

    # Initializes a new Server object with ZabbixApi Client and its API version
    #
    # No request is sent: `Client#api_version` requested the version at connect and memoises it,
    # so a long-lived process keeps reporting the version seen then.
    #
    # @param client [ZabbixApi::Client]
    # @return [ZabbixApi::Server]
    def initialize(client)
      @client = client
      @version = @client.api_version
    end
  end
end
