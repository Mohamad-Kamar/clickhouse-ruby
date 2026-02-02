# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse Tuple type
    #
    # Tuples are fixed-size collections where each position has its own type.
    # Similar to Ruby arrays but heterogeneous and fixed-size.
    #
    # @example
    #   type = Tuple.new('Tuple', arg_types: [String.new('String'), Integer.new('UInt64')])
    #   type.cast(['hello', 42])
    #   type.serialize(['hello', 42]) # => "('hello', 42)"
    #
    class Tuple < Base
      # @return [Array<Base>] the types of each tuple element
      attr_reader :element_types

      # @param name [String] the type name
      # @param arg_types [Array<Base>] the element types
      def initialize(name, arg_types: nil)
        super(name)
        @element_types = arg_types || []
      end

      # Converts a Ruby value to a tuple (Array)
      #
      # @param value [Object] the value to convert
      # @return [Array, nil] the tuple value
      # @raise [TypeCastError] if the value cannot be converted
      def cast(value)
        return nil if value.nil?

        arr = case value
              when ::Array
                value
              when ::String
                parse_tuple_string(value)
              else
                raise TypeCastError.new(
                  "Cannot cast #{value.class} to Tuple",
                  from_type: value.class.name,
                  to_type: to_s,
                  value: value,
                )
              end

        cast_elements(arr)
      end

      # Converts a value from ClickHouse to a Ruby Array
      #
      # @param value [Object] the value from ClickHouse
      # @return [Array, nil] the tuple value
      def deserialize(value)
        return nil if value.nil?

        arr = case value
              when ::Array
                value
              when ::String
                parse_tuple_string(value)
              else
                [value]
              end

        deserialize_elements(arr)
      end

      # Converts a tuple to SQL literal
      #
      # @param value [Array, nil] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return "NULL" if value.nil?

        elements = value.each_with_index.map do |v, i|
          type = @element_types[i] || Base.new("String")
          type.serialize(v)
        end

        "(#{elements.join(", ")})"
      end

      # Returns the full type string including element types
      #
      # @return [String] the type string
      def to_s
        type_strs = @element_types.map(&:to_s).join(", ")
        "Tuple(#{type_strs})"
      end

      private

      # Casts each element using its corresponding type
      #
      # @param arr [Array] the array to cast
      # @return [Array] the cast array
      def cast_elements(arr)
        arr.each_with_index.map do |v, i|
          type = @element_types[i] || Base.new("String")
          type.cast(v)
        end
      end

      # Deserializes each element using its corresponding type
      #
      # @param arr [Array] the array to deserialize
      # @return [Array] the deserialized array
      def deserialize_elements(arr)
        arr.each_with_index.map do |v, i|
          type = @element_types[i] || Base.new("String")
          type.deserialize(v)
        end
      end

      # Parses a ClickHouse tuple string representation
      #
      # @param value [String] the string to parse
      # @return [Array] the parsed tuple
      def parse_tuple_string(value)
        stripped = value.strip

        # Handle empty tuple
        return [] if stripped == "()"

        # Remove outer parentheses
        unless stripped.start_with?("(") && stripped.end_with?(")")
          raise TypeCastError.new(
            "Invalid tuple format: '#{value}'",
            from_type: "String",
            to_type: to_s,
            value: value,
          )
        end

        inner = stripped[1...-1]
        return [] if inner.strip.empty?

        # Parse elements
        parse_elements(inner)
      end

      # Parses comma-separated elements, handling nesting and quotes
      #
      # @param str [String] the inner tuple string
      # @return [Array] the parsed elements
      def parse_elements(str)
        elements = []
        current = ""
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
          when "\\"
            escape_next = true
            current += char
          when "'"
            in_string = !in_string
            current += char
          when "(", "[", "{"
            depth += 1 unless in_string
            current += char
          when ")", "]", "}"
            depth -= 1 unless in_string
            current += char
          when ","
            if depth.zero? && !in_string
              elements << parse_element(current.strip)
              current = ""
            else
              current += char
            end
          else
            current += char
          end
        end

        # Don't forget the last element
        elements << parse_element(current.strip) unless current.strip.empty?

        elements
      end

      # Parses a single element, removing quotes if necessary
      #
      # @param str [String] the element string
      # @return [Object] the parsed element
      def parse_element(str)
        if str.start_with?("'") && str.end_with?("'")
          str[1...-1].gsub("\\'", "'")
        else
          str
        end
      end
    end
  end
end
