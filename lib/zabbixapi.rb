require 'zabbixapi/version'
require 'zabbixapi/client'

require 'zabbixapi/basic/basic_alias'
require 'zabbixapi/basic/basic_func'
require 'zabbixapi/basic/basic_init'
require 'zabbixapi/basic/basic_logic'

require 'zabbixapi/classes/actions'
require 'zabbixapi/classes/applications'
require 'zabbixapi/classes/configurations'
require 'zabbixapi/classes/errors'
require 'zabbixapi/classes/events'
require 'zabbixapi/classes/graphs'
require 'zabbixapi/classes/hostgroups'
require 'zabbixapi/classes/hosts'
require 'zabbixapi/classes/httptests'
require 'zabbixapi/classes/items'
require 'zabbixapi/classes/maintenance'
require 'zabbixapi/classes/mediatypes'
require 'zabbixapi/classes/proxies'
require 'zabbixapi/classes/proxygroup'
require 'zabbixapi/classes/problems'
require 'zabbixapi/classes/roles'
require 'zabbixapi/classes/screens'
require 'zabbixapi/classes/scripts'
require 'zabbixapi/classes/server'
require 'zabbixapi/classes/templates'
require 'zabbixapi/classes/triggers'
require 'zabbixapi/classes/unusable'
require 'zabbixapi/classes/usergroups'
require 'zabbixapi/classes/usermacros'
require 'zabbixapi/classes/users'
require 'zabbixapi/classes/valuemaps'
require 'zabbixapi/classes/drules'

class ZabbixApi
  # @return [ZabbixApi::Client]
  attr_reader :client

  # Initializes a new ZabbixApi object
  #
  # @param options [Hash]
  # @return [ZabbixApi]
  def self.connect(options = {})
    new(options)
  end

  # @return [ZabbixApi]
  def self.current
    @current ||= ZabbixApi.new
  end

  # Executes an API request directly using a custom query
  #
  # @param data [Hash]
  # @return [Hash]
  def query(data)
    @client.api_request(method: data[:method], params: data[:params])
  end

  # Invalidate current authentication token
  # @return [Boolean]
  def logout
    @client.logout
  end

  # Initializes a new ZabbixApi object
  #
  # @param options [Hash]
  # @return [ZabbixApi::Client]
  def initialize(options = {})
    @client = Client.new(options)
  end

  # @return [ZabbixApi::Actions]
  def actions
    @actions ||= Actions.new(@client)
  end

  # @return [ZabbixApi::Applications]
  def applications
    @applications ||= Applications.new(@client)
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

  # @return [ZabbixApi::Screens]
  def screens
    @screens ||= Screens.new(@client)
  end

  # @return [ZabbixApi::Scripts]
  def scripts
    @scripts ||= Scripts.new(@client)
  end

  # @return [ZabbixApi::Server]
  def server
    @server ||= Server.new(@client)
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
