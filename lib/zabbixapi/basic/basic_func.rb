class ZabbixApi
  class Basic
    # Print a message to stdout when the client's `debug` option is set
    #
    # @param message [String]
    def log(message)
      puts message if @client.options[:debug]
    end

    # Whether two hashes agree on every key they share, after {#normalize_hash}
    #
    # @param first_hash [Hash]
    # @param second_hash [Hash]
    # @return [Boolean]
    def hash_equals?(first_hash, second_hash)
      normalized_first_hash = normalize_hash(first_hash)
      normalized_second_hash = normalize_hash(second_hash)

      hash1 = normalized_first_hash.merge(normalized_second_hash)
      hash2 = normalized_second_hash.merge(normalized_first_hash)
      hash1 == hash2
    end

    # Fetch the object id out of a dump_by_id-style argument, or raise
    #
    # A get sent without the id would return every object instead of one.
    #
    # @param data [Hash] the object's id under {#key}
    # @param extra [Array<Symbol>] further accepted key names, such as the `:id` Roles accepts
    # @raise [ApiError] when none of the accepted keys carries a value
    # @return [String, Integer] the id that was supplied
    def require_id!(data, *extra)
      require_field!(data, key, 'dump_by_id', *extra)
    end

    # Fetch a required value out of a caller's hash, or raise
    #
    # The general form of {#require_id!}. Zabbix ignores a null filter value, so a lookup sent
    # without its value would return every object instead of the one asked for.
    #
    # @param data [Hash] the caller's parameters
    # @param field [String, Symbol] the required field
    # @param caller_name [String] method name to name in the error message
    # @param extra [Array<Symbol>] additional accepted key names
    # @raise [ApiError] when none of the accepted keys carries a value other than nil or false
    # @return [Object] the value that was supplied
    def require_field!(data, field, caller_name, *extra)
      names = ([field.to_sym, field.to_s] + extra.flat_map { |e| [e.to_sym, e.to_s] }).uniq
      value = names.filter_map { |name| data[name] }.first
      raise ApiError.new("#{field} not supplied in call to #{caller_name}") if value.nil?

      value
    end

    # Reduce a lookup's rows to the one id they identify, or raise
    #
    # Zabbix does not keep the {#identify} value unique for every object type, so a lookup can
    # match several.
    #
    # @param rows [Array<Hash>] the rows that matched, already selected by the caller
    # @param id_field [String] the property carrying the id
    # @param caller_name [String] method name to name in the error message
    # @raise [ApiError] when the rows carry more than one distinct id
    # @return [Integer, nil] the single id, or nil when nothing matched
    def one_id!(rows, id_field, caller_name)
      ids = rows.filter_map { |row| row[id_field] }.uniq
      raise ApiError.new("#{caller_name} matched #{ids.size} #{method_name} objects, not one (#{id_field} #{ids.join(', ')}): narrow the lookup") if ids.size > 1

      ids.first&.to_i
    end

    # Drop nil values, and nested hashes left empty, from request parameters at every depth
    #
    # Zabbix ignores a null filter value without documenting it, so no request relies on that.
    # `false`, `0`, `''` and `[]` are values and are kept.
    #
    # @param params [Hash]
    # @return [Hash] the same parameters without nil values or emptied sub-objects
    def compact_params(params)
      params.each_with_object({}) do |(name, value), kept|
        value = compact_params(value) if value.is_a?(Hash)
        next if value.nil? || (value.is_a?(Hash) && value.empty?)

        kept[name] = value
      end
    end

    # Whether an update can safely be skipped because the server already holds the given data
    #
    # Every field but the id must be in the dump: {#hash_equals?} ignores a key one side lacks,
    # and `output: extend` returns no related collection, such as interfaces, macros, tags or
    # templates, unless a select* parameter asks for it.
    #
    # @param dump [Hash] current state as returned by dump_by_id
    # @param data [Hash] payload the caller wants to apply
    # @return [Boolean]
    def skip_update?(dump, data)
      (data.keys - [key.to_sym]).all? { |field| dump.key?(field) } && hash_equals?(dump, data)
    end

    # Convert all hash/array keys to symbols, leaving the argument untouched
    #
    # @param object [Array, Hash, Object]
    # @return [Array, Hash, Object] a symbol-keyed copy, or the object itself when it is neither
    def symbolize_keys(object)
      case object
      when Array then object.map { |value| symbolize_keys(value) }
      when Hash then object.each_with_object({}) { |(name, value), result| result[name.to_sym] = symbolize_keys(value) }
      else object
      end
    end

    # Normalize all hash values to strings, arrays element by element, and remove `:hostid`
    #
    # @param hash [Hash]
    # @return [Hash]
    def normalize_hash(hash)
      result = hash.dup

      result.delete(:hostid)

      result.each do |key, value|
        result[key] = value.is_a?(Array) ? normalize_array(value) : value.to_s
      end

      result
    end

    # Normalize all array values to strings
    #
    # @param array [Array]
    # @return [Array]
    def normalize_array(array)
      result = []

      array.each do |e|
        if e.is_a?(Array)
          result.push(normalize_array(e))
        elsif e.is_a?(Hash)
          result.push(normalize_hash(e))
        else
          result.push(e.to_s)
        end
      end

      result
    end

    # Parse a data hash for id key or boolean to return
    #
    # The gem's own calls always pass the Hash that create, update and delete answer under
    # {#keys}; the Boolean branch serves external callers.
    #
    # `bulk` follows the call, not the result: a bulk create that made one object still answers
    # an Array.
    #
    # @param data [Hash, Boolean] An API result hash, or a Boolean to pass through
    # @param bulk [Boolean] whether the request carried an Array of objects or ids
    # @return [Integer, Array<Integer>, Boolean, nil] the first id under the plural key, every id
    #   when bulk, the same Boolean back for a Boolean, or nil for an empty Hash or other input
    def parse_keys(data, bulk = false)
      case data
      when Hash
        return nil if data.empty?

        bulk ? data[keys].map(&:to_i) : data[keys][0].to_i
      when TrueClass
        true
      when FalseClass
        false
      end
    end

    # Merge two hashes into a single new hash
    #
    # @param first_hash [Hash]
    # @param second_hash [Hash]
    # @return [Hash]
    def merge_params(first_hash, second_hash)
      new = first_hash.dup
      new.merge(second_hash)
    end

    # Merge a class's default_options under the caller's payload, dropping the placeholders
    #
    # A nil in default_options marks a required field without a value. It is dropped unless the
    # caller set that field, so an omitted field is absent from the request rather than null; a
    # nil the caller wrote is sent.
    #
    # @param data [Hash] the caller's payload, already normalised to symbol keys
    # @return [Hash] the payload with the class's defaults merged under it
    def merge_defaults(data)
      merge_params(default_options, data).reject { |field, value| value.nil? && !data.key?(field) }
    end
  end
end
