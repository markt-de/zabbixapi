module Live
  # The interlock for Roles, Usergroups and Users, whose writes can revoke the credential the run
  # uses: a baseline of every role, group and user before the first write, a guard that refuses any
  # write target predating the spec, and a check that the credential still works.
  module Interlock
    SELECTS = {
      'role' => { selectRules: 'extend', selectUsers: 'extend' },
      'usergroup' => { selectUsers: 'extend', selectHostGroupRights: 'extend', selectTemplateGroupRights: 'extend', selectTagFilters: 'extend' },
      'user' => { selectUsrgrps: 'extend', selectRole: 'extend', selectMedias: 'extend' }
    }.freeze
    ID_FIELD = { 'role' => 'roleid', 'usergroup' => 'usrgrpid', 'user' => 'userid' }.freeze
    NAME_FIELD = { 'role' => 'name', 'usergroup' => 'name', 'user' => 'username' }.freeze
    # Read-only user fields that failed logins move; comparing them would manufacture noise.
    VOLATILE = %w[attempt_clock attempt_failed attempt_ip].freeze

    @baseline = {}
    @owner = nil

    class << self
      attr_reader :owner

      # Resolve the token's owner (never assumed to be Admin) and snapshot everything that predates
      # the spec. The token travels as a parameter here and Client#pretty_body masks it, so a
      # failure cannot quote it back.
      def establish!
        @owner = Live.retrying('checkAuthentication') { Live.session.query(method: 'user.checkAuthentication', params: { token: Live.token }) }
        SELECTS.each_key { |object| @baseline[object] = snapshot(object) }
        raise 'interlock: the token owner is not in the baseline' unless protected?('user', @owner['userid'])

        @owner
      end

      def snapshot(object)
        Live.get(object, SELECTS.fetch(object)).to_h { |row| [row[ID_FIELD.fetch(object)], canon(row)] }
      end

      # Sub-selects come back in no guaranteed order and the volatile fields move by themselves.
      def canon(value)
        case value
        when Hash then value.except(*VOLATILE).map { |key, item| [key, canon(item)] }.sort_by(&:first)
        when Array then value.map { |item| canon(item) }.sort_by(&:inspect)
        else value.to_s
        end
      end

      def protected?(object, id)
        @baseline.fetch(object).key?(id.to_s)
      end

      # Name every write target through this; it raises for any id that predates the spec.
      def safe(object, id)
        raise "INTERLOCK: refusing to write to #{object} #{id}, it predates the spec" if protected?(object, id)

        id
      end

      def default_id(object, name)
        found = @baseline.fetch(object).find { |_, row| row.to_h[NAME_FIELD.fetch(object)] == name }
        raise "no default #{object} named #{name.inspect}" if found.nil?

        found.first
      end

      # A fresh connection with the token, then a read of the owner: the credential still
      # authenticates and the role still permits API calls. Returns the owner's username, nil when
      # the read finds no row.
      def alive!
        fresh = Live.retrying('reconnect') { ZabbixApi.connect(url: Live.url, token: Live.token) }
        rows = fresh.query(method: 'user.get', params: { output: %w[userid username], userids: [@owner['userid']] })
        rows.first && rows.first['username']
      end

      # Ids that vanished or changed since the baseline, per object; ids added since do not predate
      # the spec and are left out.
      def changed
        SELECTS.each_key.with_object({}) do |object, out|
          now = snapshot(object)
          before = @baseline.fetch(object)
          missing = before.keys - now.keys
          altered = (before.keys & now.keys).reject { |id| before[id] == now[id] }
          out[object] = { missing: missing, changed: altered } unless missing.empty? && altered.empty?
        end
      end

      def assert_unchanged!
        diff = changed
        raise "INTERLOCK: objects that predate the spec changed: #{diff.inspect}" unless diff.empty?

        true
      end
    end
  end
end
