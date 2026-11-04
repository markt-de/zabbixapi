class ZabbixApi
  # Wrapper for the `usergroup` API object.
  class Usergroups < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'usergroup'
    end

    # The id field name, `usrgrpid` in the API rather than the derived `usergroupid`
    #
    # @return [String]
    def key
      'usrgrpid'
    end

    # The field a user group is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Set permissions for usergroup using Zabbix API
    #
    # Replaces the group's host group permissions with the given host groups, each at
    # `permission`, which defaults to 2, read-only access.
    #
    # @param data [Hash] usrgrpid, the hostgroupids to grant, and optionally permission
    # @return [Integer, nil] Zabbix object id (usergroup), or nil when the server returns no result
    def permissions(data)
      data = symbolize_keys(data)
      permission = data[:permission] || 2
      result = @client.api_request(
        method: "#{method_name}.update",
        params: {
          usrgrpid: data[:usrgrpid],
          hostgroup_rights: data[:hostgroupids].map { |t| { permission: permission, id: t } }
        }
      )
      result ? result['usrgrpids'][0].to_i : nil
    end

    # Set the user list of one or more user groups using the Zabbix API
    #
    # `usergroup.update`'s `users` parameter replaces the current membership rather than
    # adding to it, and the Zabbix API offers no append call. Every user who is to remain in a
    # group must therefore be named in `userids`, or they are removed from it, losing whatever
    # access that group granted them.
    #
    # @param data [Hash] Needs usrgrpids (Array of user group ids) and userids (Array of user
    #   ids), which together become each named group's complete user list
    # @return [Integer, nil] the id of the first group updated, or nil when the server returns no
    #   result
    def update_users(data)
      data = symbolize_keys(data)
      user_groups = data[:usrgrpids].map do |t|
        {
          usrgrpid: t,
          users: data[:userids].map { |u| { userid: u } }
        }
      end
      result = @client.api_request(
        method: "#{method_name}.update",
        params: user_groups
      )
      result ? result['usrgrpids'][0].to_i : nil
    end
  end
end
