class ZabbixApi
  # Wrapper for the `trigger` API object.
  class Triggers < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'trigger'
    end

    # The field a trigger is looked up by; the API keeps a trigger's name in `description`
    #
    # @return [String]
    def identify
      'description'
    end

    # Dump Trigger object data by key from Zabbix API
    #
    # Returns each trigger with its expression expanded and its items and functions selected.
    #
    # @param data [Hash] the trigger's id under {#key}
    # @raise [ApiError] when data carries no id
    # @return [Array<Hash>]
    def dump_by_id(data)
      log "[DEBUG] Call dump_by_id with parameters: #{data.inspect}"

      @client.api_request(
        method: "#{method_name}.get",
        params: {
          filter: {
            key.to_sym => require_id!(data)
          },
          output: 'extend',
          # Without this the expression comes back with {functionid} references
          # ("{37022}<1") instead of the readable form callers write
          # ("last(/host/key)<1"), which makes any comparison meaningless.
          expandExpression: true,
          selectItems: 'extend',
          selectFunctions: 'extend'
        }
      )
    end

    # Replace a Trigger rather than modifying it in place
    #
    # When the given data already matches the stored trigger nothing happens. Otherwise the
    # existing trigger is deleted and a new one is created from the data.
    #
    # A plain {#update} changes a trigger's expression as well, and since this method destroys
    # the old trigger - along with its event and problem history - {#update} is the better
    # choice unless a genuinely new trigger is what you want.
    # The old trigger is removed *before* the new one is created, because creating first
    # would collide with the existing trigger whenever the expression itself is unchanged;
    # the consequence is that an invalid definition leaves nothing behind.
    #
    # Comparison relies on `expandExpression` in {#dump_by_id}, so the stored expression is
    # compared in the same `func(/host/key)` form the caller writes. Fields the dump cannot
    # return - the `tags` and `dependencies` collections need their own select parameters -
    # cannot be proven equal, so supplying them always triggers the replacement.
    #
    # @param data [Hash] Full trigger definition, including the triggerid to replace
    # @raise [ApiError] when data carries no triggerid, or no trigger has it
    # @return [Integer, nil] The existing triggerid when unchanged, otherwise the new trigger's id,
    #   or nil when the create result is empty
    def replace(data)
      log "[DEBUG] Call replace with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      triggerid = data[key.to_sym].to_i
      stored = dump_by_id(key.to_sym => data[key.to_sym]).find { |trigger| trigger[key].to_i == triggerid }
      raise ApiError.new("Trigger #{triggerid} not found, cannot replace it") if stored.nil?

      # Compare only what the caller actually supplied; items/functions are metadata the
      # dump carries for convenience and are not update parameters.
      current = symbolize_keys(stored).select { |field, _| data.key?(field) }
      log "[DEBUG] stored trigger is: #{current}"

      if skip_update?(current, data)
        log "[DEBUG] Equal keys #{current} and #{data}, skip replace"
        return triggerid
      end

      log "[DEBUG] delete old trigger: #{delete(triggerid).inspect}"

      # templateid is read-only and triggerid must not be present when creating.
      create(data.reject { |field, _| [key.to_sym, :templateid].include?(field) })
    end

    # Get or Create Trigger object using Zabbix API
    #
    # `hostid` scopes the lookup to one host, where a description can repeat under another
    # expression, and must not reach the create: `trigger.create` rejects it as an unexpected
    # parameter, because a trigger's host is derived from the items referenced in its expression.
    #
    # @param data [Hash] Needs to include description and hostid, the fields the lookup filters on
    # @raise [ApiError] when data carries no description, or more than one trigger matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the create result is empty
    def get_or_create(data)
      log "[DEBUG] Call get_or_create with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      unless (id = get_id(description: data[:description], hostid: data[:hostid]))
        id = create(data.reject { |field, _| field == :hostid })
      end
      id
    end

    # Create or update a Trigger object using the Zabbix API
    #
    # `hostid` scopes the lookup to one host, where a description can repeat under another
    # expression, and reaches neither branch: `trigger.create` rejects it outright and an
    # update has no use for it.
    #
    # This updates an existing trigger in place; {#get_or_create} leaves it untouched, and
    # {#replace} destroys and rebuilds it.
    #
    # @param data [Hash] Needs to include description and hostid, the fields the lookup filters on
    # @raise [ApiError] when data carries no description, or more than one trigger matches the lookup
    # @return [Integer, nil] Zabbix object id, or nil when the result is empty
    def create_or_update(data)
      log "[DEBUG] Call create_or_update with parameters: #{data.inspect}"

      data = symbolize_keys(data)
      scoped = data.reject { |field, _| field == :hostid }
      triggerid = get_id(description: data[:description], hostid: data[:hostid])

      triggerid ? update(scoped.merge(triggerid: triggerid)) : create(scoped)
    end
  end
end
