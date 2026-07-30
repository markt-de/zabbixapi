class ZabbixApi
  class Basic
    # Log messages to stdout when debugging
    #
    # @param message [String]
    def log(message)
      puts message if @client.options[:debug]
    end

    # Compare two hashes for equality
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

    # Convert all hash/array keys to symbols
    #
    # @param object [Array, Hash]
    # @return [Array, Hash]
    def symbolize_keys(object)
      if object.is_a?(Array)
        object.each_with_index do |val, index|
          object[index] = symbolize_keys(val)
        end
      elsif object.is_a?(Hash)
        object.keys.each do |key|
          object[key.to_sym] = symbolize_keys(object.delete(key))
        end
      end
      object
    end

    # Normalize all hash values to strings
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
    # @param data [Hash]
    # @return [Integer] The object id if a single object hash is provided with key
    # @return [Boolean] True/False if multiple class object hash is provided
    def parse_keys(data)
      case data
      when Hash
        data.empty? ? nil : data[keys][0].to_i
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
  end
end
