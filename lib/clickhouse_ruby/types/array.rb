# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse Array type
    #
    # Arrays in ClickHouse are homogeneous - all elements must be the same type.
    # Supports nested arrays like Array(Array(String)).
    #
    # @example
    #   type = Array.new('Array', element_type: String.new('String'))
    #   type.cast(['a', 'b', 'c'])  # => ['a', 'b', 'c']
    #   type.serialize(['a', 'b']) # => "['a', 'b']"
    #
    class Array < Base
      # @return [Base] the type of array elements
      attr_reader :element_type

      # @param name [String] the type name
      # @param element_type [Base] the element type
      def initialize(name, element_type: nil)
        super(name)
        @element_type = element_type || Base.new('String')
      end

      # Converts a Ruby value to an array
      #
      # @param value [Object] the value to convert
      # @return [Array, nil] the array value
      # @raise [TypeCastError] if the value cannot be converted
      def cast(value)
        return nil if value.nil?

        arr = case value
              when ::Array
                value
              when ::String
                parse_array_string(value)
              else
                raise TypeCastError.new(
                  "Cannot cast #{value.class} to Array",
                  from_type: value.class.name,
                  to_type: to_s,
                  value: value
                )
              end

        arr.map { |v| @element_type.cast(v) }
      end

      # Converts a value from ClickHouse to a Ruby Array
      #
      # @param value [Object] the value from ClickHouse
      # @return [Array, nil] the array value
      def deserialize(value)
        return nil if value.nil?

        arr = case value
              when ::Array
                value
              when ::String
                parse_array_string(value)
              else
                [value]
              end

        arr.map { |v| @element_type.deserialize(v) }
      end

      # Converts an array to SQL literal
      #
      # @param value [Array, nil] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return 'NULL' if value.nil?

        elements = value.map { |v| @element_type.serialize(v) }
        "[#{elements.join(', ')}]"
      end

      # Returns the full type string including element type
      #
      # @return [String] the type string
      def to_s
        "Array(#{@element_type})"
      end

      private

      # Parses a ClickHouse array string representation
      #
      # @param value [String] the string to parse
      # @return [Array] the parsed array
      def parse_array_string(value)
        stripped = value.strip

        # Handle empty array
        return [] if stripped == '[]'

        # Remove outer brackets
        unless stripped.start_with?('[') && stripped.end_with?(']')
          raise TypeCastError.new(
            "Invalid array format: '#{value}'",
            from_type: 'String',
            to_type: to_s,
            value: value
          )
        end

        inner = stripped[1...-1]
        return [] if inner.strip.empty?

        # Parse elements (handles nested arrays and quoted strings)
        parse_elements(inner)
      end

      # Parses comma-separated elements, handling nesting and quotes
      #
      # @param str [String] the inner array string
      # @return [Array] the parsed elements
      def parse_elements(str)
        elements = []
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
          when '[', '('
            depth += 1 unless in_string
            current += char
          when ']', ')'
            depth -= 1 unless in_string
            current += char
          when ','
            if depth.zero? && !in_string
              elements << parse_element(current.strip)
              current = ''
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
        # Remove surrounding quotes if present
        if str.start_with?("'") && str.end_with?("'")
          str[1...-1].gsub("\\'", "'")
        elsif str.start_with?('[')
          # Nested array - let the element type handle it
          str
        else
          str
        end
      end
    end
  end
end
