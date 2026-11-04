require 'zabbixapi/version'
require 'zabbixapi/client'

require 'zabbixapi/basic/basic_alias'
require 'zabbixapi/basic/basic_func'
require 'zabbixapi/basic/basic_init'
require 'zabbixapi/basic/basic_logic'

require 'zabbixapi/classes/actions'
require 'zabbixapi/classes/configurations'
require 'zabbixapi/classes/drules'
require 'zabbixapi/classes/errors'
require 'zabbixapi/classes/events'
require 'zabbixapi/classes/graphs'
require 'zabbixapi/classes/hostgroups'
require 'zabbixapi/classes/hosts'
require 'zabbixapi/classes/httptests'
require 'zabbixapi/classes/items'
require 'zabbixapi/classes/maintenance'
require 'zabbixapi/classes/mediatypes'
require 'zabbixapi/classes/problems'
require 'zabbixapi/classes/proxies'
require 'zabbixapi/classes/proxygroup'
require 'zabbixapi/classes/roles'
require 'zabbixapi/classes/scripts'
require 'zabbixapi/classes/server'
require 'zabbixapi/classes/templategroups'
require 'zabbixapi/classes/templates'
require 'zabbixapi/classes/triggers'
require 'zabbixapi/classes/usergroups'
require 'zabbixapi/classes/usermacros'
require 'zabbixapi/classes/users'
require 'zabbixapi/classes/valuemaps'

# The gem's entry point: one {ZabbixApi::Client}, a memoized wrapper per API object, and {#query} for raw requests.
class ZabbixApi
  # @return [ZabbixApi::Client]
  attr_reader :client

  # Initializes a new ZabbixApi object and remembers it as the process-wide current connection
  #
  # @param options [Hash]
  # @return [ZabbixApi]
  def self.connect(options = {})
    @current = new(options)
  end

  # The connection most recently established by {ZabbixApi.connect}
  #
  # @raise [ApiError] when no connection has been established yet
  # @return [ZabbixApi]
  def self.current
    raise ApiError.new('no current connection: call ZabbixApi.connect first') unless @current

    @current
  end

  # Executes an API request directly using a custom query
  #
  # `method` and `params` may be given as symbol or string keys; `params` is sent unchanged.
  #
  # @param data [Hash]
  # @return [Hash, Array, String, Boolean] the JSON-RPC result, as the server returned it
  def query(data)
    data = data.transform_keys(&:to_sym)
    @client.api_request(method: data[:method], params: data[:params])
  end

  # Ends a user.login session; a no-op returning true under token authentication
  # @return [Boolean]
  def logout
    @client.logout
  end

  # Initializes a new ZabbixApi object
  #
  # @param options [Hash]
  # @return [ZabbixApi]
  def initialize(options = {})
    @client = Client.new(options)
  end

  # @return [ZabbixApi::Actions]
  def actions
    @actions ||= Actions.new(@client)
  end

  # @return [ZabbixApi::Configurations]
  def configurations
    @configurations ||= Configurations.new(@client)
  end

  # @return [ZabbixApi::Events]
  def events
    @events ||= Events.new(@client)
  end

  # @return [ZabbixApi::Graphs]
  def graphs
    @graphs ||= Graphs.new(@client)
  end

  # @return [ZabbixApi::HostGroups]
  def hostgroups
    @hostgroups ||= HostGroups.new(@client)
  end

  # @return [ZabbixApi::Hosts]
  def hosts
    @hosts ||= Hosts.new(@client)
  end

  # @return [ZabbixApi::HttpTests]
  def httptests
    @httptests ||= HttpTests.new(@client)
  end

  # @return [ZabbixApi::Items]
  def items
    @items ||= Items.new(@client)
  end

  # @return [ZabbixApi::Maintenance]
  def maintenance
    @maintenance ||= Maintenance.new(@client)
  end

  # @return [ZabbixApi::Mediatypes]
  def mediatypes
    @mediatypes ||= Mediatypes.new(@client)
  end

  # @return [ZabbixApi::Problems]
  def problems
    @problems ||= Problems.new(@client)
  end

  # @return [ZabbixApi::Proxies]
  def proxies
    @proxies ||= Proxies.new(@client)
  end

  # @return [ZabbixApi::Proxygroup]
  def proxygroup
    @proxygroup ||= Proxygroup.new(@client)
  end

  # @return [ZabbixApi::Roles]
  def roles
    @roles ||= Roles.new(@client)
  end

  # @return [ZabbixApi::Scripts]
  def scripts
    @scripts ||= Scripts.new(@client)
  end

  # @return [ZabbixApi::Server]
  def server
    @server ||= Server.new(@client)
  end

  # @return [ZabbixApi::TemplateGroups]
  def templategroups
    @templategroups ||= TemplateGroups.new(@client)
  end

  # @return [ZabbixApi::Templates]
  def templates
    @templates ||= Templates.new(@client)
  end

  # @return [ZabbixApi::Triggers]
  def triggers
    @triggers ||= Triggers.new(@client)
  end

  # @return [ZabbixApi::Usergroups]
  def usergroups
    @usergroups ||= Usergroups.new(@client)
  end

  # @return [ZabbixApi::Usermacros]
  def usermacros
    @usermacros ||= Usermacros.new(@client)
  end

  # @return [ZabbixApi::Users]
  def users
    @users ||= Users.new(@client)
  end

  # @return [ZabbixApi::ValueMaps]
  def valuemaps
    @valuemaps ||= ValueMaps.new(@client)
  end

  # @return [ZabbixApi::Drules]
  def drules
    @drules ||= Drules.new(@client)
  end
end
