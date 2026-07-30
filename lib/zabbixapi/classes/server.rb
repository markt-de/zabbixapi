class ZabbixApi
  class Server
    # @return [String]
    attr_reader :version

    # Initializes a new Server object with ZabbixApi Client and fetches Zabbix Server API version
    #
    # @param client [ZabbixApi::Client]
    # @return [ZabbixApi::Client]
    # @return [String] Zabbix API version number
    def initialize(client)
      @client = client
      @version = @client.api_version
    end
  end
end
