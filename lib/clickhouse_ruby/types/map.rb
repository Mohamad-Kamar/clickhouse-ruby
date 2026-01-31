# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse Map type
    #
    # Maps are key-value collections where all keys share one type
    # and all values share another type.
    #
    # @example
    #   type = Map.new('Map', arg_types: [String.new('String'), Integer.new('UInt64')])
    #   type.cast({'a' => 1, 'b' => 2})
    #   type.serialize({'a' => 1}) # => "{'a': 1}"
    #
    class Map < Base
      # @return [Base] the key type
      attr_reader :key_type

      # @return [Base] the value type
      attr_reader :value_type

      # @param name [String] the type name
      # @param arg_types [Array<Base>] array of [key_type, value_type]
      def initialize(name, arg_types: nil)
        super(name)
        arg_types ||= [Base.new('String'), Base.new('String')]
        @key_type = arg_types[0]
        @value_type = arg_types[1] || Base.new('String')
      end

      # Converts a Ruby value to a map (Hash)
      #
      # @param value [Object] the value to convert
      # @return [Hash, nil] the hash value
      # @raise [TypeCastError] if the value cannot be converted
      def cast(value)
        return nil if value.nil?

        hash = case value
               when ::Hash
                 value
               when ::String
                 parse_map_string(value)
               else
                 raise TypeCastError.new(
                   "Cannot cast #{value.class} to Map",
                   from_type: value.class.name,
                   to_type: to_s,
                   value: value
                 )
               end

        hash.transform_keys { |k| @key_type.cast(k) }
            .transform_values { |v| @value_type.cast(v) }
      end

      # Converts a value from ClickHouse to a Ruby Hash
      #
      # @param value [Object] the value from ClickHouse
      # @return [Hash, nil] the hash value
      def deserialize(value)
        return nil if value.nil?

        hash = case value
               when ::Hash
                 value
               when ::String
                 parse_map_string(value)
               else
                 { value => nil }
               end

        hash.transform_keys { |k| @key_type.deserialize(k) }
            .transform_values { |v| @value_type.deserialize(v) }
      end

      # Converts a hash to SQL literal
      #
      # @param value [Hash, nil] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return 'NULL' if value.nil?

        pairs = value.map do |k, v|
          "#{@key_type.serialize(k)}: #{@value_type.serialize(v)}"
        end

        "{#{pairs.join(', ')}}"
      end

      # Returns the full type string including key and value types
      #
      # @return [String] the type string
      def to_s
        "Map(#{@key_type}, #{@value_type})"
      end

      private

      # Parses a ClickHouse map string representation
      #
      # @param value [String] the string to parse
      # @return [Hash] the parsed hash
      def parse_map_string(value)
        stripped = value.strip

        # Handle empty map
        return {} if stripped == '{}'

        # Remove outer braces
        unless stripped.start_with?('{') && stripped.end_with?('}')
          raise TypeCastError.new(
            "Invalid map format: '#{value}'",
            from_type: 'String',
            to_type: to_s,
            value: value
          )
        end

        inner = stripped[1...-1]
        return {} if inner.strip.empty?

        # Parse key-value pairs
        parse_pairs(inner)
      end

      # Parses comma-separated key:value pairs
      #
      # @param str [String] the inner map string
      # @return [Hash] the parsed pairs
      def parse_pairs(str)
        result = {}
        current = ''
        depth = 0
        in_string = false
        escape_next = false

        str.each_char do |char|
          if escape_next
            current += char
            escape_next = false
            next
          end

          case char
          when '\\'
            escape_next = true
            current += char
          when "'"
            in_string = !in_string
            current += char
          when '{', '[', '('
            depth += 1 unless in_string
            current += char
          when '}', ']', ')'
            depth -= 1 unless in_string
            current += char
          when ','
            if depth.zero? && !in_string
              key, value = parse_pair(current.strip)
              result[key] = value
              current = ''
            else
              current += char
            end
          else
            current += char
          end
        end

        # Don't forget the last pair
        unless current.strip.empty?
          key, value = parse_pair(current.strip)
          result[key] = value
        end

        result
      end

      # Parses a single key:value pair
      #
      # @param str [String] the pair string
      # @return [Array] [key, value]
      def parse_pair(str)
        # Find the colon separator (not inside quotes or nested structures)
        colon_idx = find_separator(str, ':')

        if colon_idx.nil?
          raise TypeCastError.new(
            "Invalid map pair format: '#{str}'",
            from_type: 'String',
            to_type: to_s,
            value: str
          )
        end

        key = parse_value(str[0...colon_idx].strip)
        value = parse_value(str[(colon_idx + 1)..].strip)

        [key, value]
      end

      # Finds the index of a separator character, ignoring nested structures
      #
      # @param str [String] the string to search
      # @param sep [String] the separator character
      # @return [Integer, nil] the index or nil if not found
      def find_separator(str, sep)
        depth = 0
        in_string = false
        escape_next = false

        str.each_char.with_index do |char, idx|
          if escape_next
            escape_next = false
            next
          end

          case char
          when '\\'
            escape_next = true
          when "'"
            in_string = !in_string
          when '{', '[', '('
            depth += 1 unless in_string
          when '}', ']', ')'
            depth -= 1 unless in_string
          when sep
            return idx if depth.zero? && !in_string
          end
        end

        nil
      end

      # Parses a value, removing quotes if necessary
      #
      # @param str [String] the value string
      # @return [Object] the parsed value
      def parse_value(str)
        if str.start_with?("'") && str.end_with?("'")
          str[1...-1].gsub("\\'", "'")
        else
          str
        end
      end
    end
  end
end
