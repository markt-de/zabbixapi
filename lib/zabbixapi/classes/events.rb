class ZabbixApi
  # Wrapper for the `event` API object, read-only but for {#acknowledge}.
  class Events < Basic
    # The Zabbix API object name
    #
    # @return [String]
    def method_name
      'event'
    end

    # The field an event is looked up by
    #
    # @return [String]
    def identify
      'name'
    end

    # Update one or more events, the only write the Zabbix event API offers
    #
    # `eventids` and `action` are both required. `action` is a bitmask - 1 close, 2 acknowledge,
    # 4 add message, 8 change severity, 16 unacknowledge, 32 suppress, 64 unsuppress, 128 rank as
    # cause, 256 rank as symptom - and any sum is accepted, so 38 acknowledges, adds a message and
    # suppresses in one call. `message`, `severity`, `suppress_until` and `cause_eventid` are each
    # required only for the bit that uses them. The API reference calls 6 the acknowledge bit; it
    # is 2+4 and needs a `message`.
    #
    # Only trigger events, and only problem events, can be updated; an action the event is already
    # in is skipped rather than refused. An empty `eventids` list is refused here rather than sent:
    # the server accepts it and writes nothing.
    #
    # @example Acknowledge one event and leave a message
    #   acknowledge(eventids: 20427, action: 6, message: 'Problem resolved.')
    #
    # @param data [Hash] Needs eventids and action, plus whatever the action's bits require
    # @raise [ApiError] when eventids names nothing
    # @return [Array<Integer>] the ids of the events the server updated
    def acknowledge(data)
      data = symbolize_keys(data)
      raise ApiError.new('Events#acknowledge was given no eventid: the server accepts an empty list and writes nothing') if Array(data[:eventids]).empty?

      Array(@client.api_request(method: "#{method_name}.acknowledge", params: data)[keys]).map(&:to_i)
    end

    [:create, :delete, :update, :create_or_update, :get_or_create].each do |unsupported|
      define_method(unsupported) do |*|
        raise ApiError.new("Events##{unsupported} is not supported: the Zabbix event API only provides event.get and event.acknowledge")
      end
    end
  end
end
