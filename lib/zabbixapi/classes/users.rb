class ZabbixApi
  # Wrapper for the `user` API object.
  class Users < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'user'
    end

    # The field a user is looked up by
    #
    # @return [String]
    def identify
      'username'
    end

    # Set the media list of one or more users using the Zabbix API
    #
    # `user.update`'s `medias` parameter replaces the user's existing non-provisioned media
    # rather than adding to it, and the Zabbix API offers no "append media" call.
    # Every medium that is to survive must therefore be named in `medias`, or it is removed.
    #
    # @param data [Hash] Needs userids (Array of user ids) and medias (Array of media objects),
    #   which together become each named user's complete media list
    # @raise [ApiError] when userids or medias is not supplied
    # @return [Integer, nil] The first affected user id, or nil if the API returned nothing
    def update_medias(data)
      userids = require_field!(data, 'userids', 'update_medias')
      medias = require_field!(data, 'medias', 'update_medias')

      result = @client.api_request(
        method: "#{method_name}.update",
        params: userids.map do |t|
          {
            userid: t,
            medias: medias
          }
        end
      )
      result ? result['userids'][0].to_i : nil
    end
  end
end
