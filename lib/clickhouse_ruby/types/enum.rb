# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse Enum types
    #
    # Handles: Enum, Enum8, Enum16
    #
    # Enum types store predefined string values as integers for efficient storage.
    # Supports both explicit value assignment ('name' = value) and auto-increment syntax.
    #
    class Enum < Base
      # @return [Array<String>] the list of possible enum values
      attr_reader :possible_values

      # @return [Hash{String => Integer}] mapping of string values to integers
      attr_reader :value_to_int

      # @return [Hash{Integer => String}] mapping of integers to string values
      attr_reader :int_to_value

      def initialize(name, arg_types: nil)
        super(name)

        # When called from registry, we get arg_types with parsed enum entries.
        # When called directly (for testing), we get the full name like "Enum8('active' = 1, 'inactive' = 2)"
        if arg_types && !arg_types.empty?
          @possible_values, @value_to_int, @int_to_value = parse_enum_from_args(name, arg_types)
        else
          @possible_values, @value_to_int, @int_to_value = parse_enum_definition(name)
        end
      end

      # Converts a Ruby value to a valid enum value
      #
      # @param value [String, Integer, nil] the value to convert
      # @return [String, nil] the enum value (string)
      # @raise [TypeCastError] if value is not a valid enum value
      def cast(value)
        return nil if value.nil?

        case value
        when ::String
          validate_string_value!(value)
          value
        when ::Integer
          validate_int_value!(value)
          @int_to_value[value]
        else
          raise TypeCastError.new(
            "Cannot cast #{value.class} to #{self}",
            from_type: value.class.name,
            to_type: to_s,
            value: value,
          )
        end
      end

      # Converts a value from ClickHouse response format to Ruby
      #
      # @param value [Object] the value from ClickHouse
      # @return [String] the string value
      def deserialize(value)
        value.to_s
      end

      # Converts a Ruby value to ClickHouse SQL literal format
      #
      # @param value [String, nil] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return "NULL" if value.nil?

        escaped = value.to_s.gsub("'", "\\\\'")
        "'#{escaped}'"
      end

      private

      # Parses an Enum from registry arg_types
      #
      # The arg_types are Base type objects where the :type is the enum entry string
      #
      # @param name [String] the type name (e.g., "Enum8")
      # @param arg_types [Array<Base>] the parsed enum entries
      # @return [Array] [possible_values, value_to_int, int_to_value]
      def parse_enum_from_args(_name, arg_types)
        possible_values = []
        value_to_int = {}
        int_to_value = {}
        auto_index = 1

        arg_types.each do |arg_type|
          # The arg_type.name contains the enum entry string
          entry = arg_type.name
          enum_name, int_val = parse_enum_entry(entry)

          possible_values << enum_name

          # If no explicit value, use auto-increment
          if int_val.nil?
            int_val = auto_index
            auto_index += 1
          elsif int_val >= auto_index
            auto_index = int_val + 1
          end

          value_to_int[enum_name] = int_val
          int_to_value[int_val] = enum_name
        end

        [possible_values, value_to_int, int_to_value]
      end

      # Parses an Enum type definition to extract values and mappings
      #
      # Handles both syntaxes:
      # - Explicit: Enum8('active' = 1, 'inactive' = 2)
      # - Auto-increment: Enum('hello', 'world')  # hello=1, world=2
      #
      # @param type_string [String] the full type string (e.g., "Enum8('active' = 1)")
      # @return [Array] [possible_values, value_to_int, int_to_value]
      def parse_enum_definition(type_string)
        # Extract the part inside parentheses
        # e.g., Enum8('active' = 1, 'inactive' = 2) -> 'active' = 1, 'inactive' = 2
        match = type_string.match(/\((.*)\)\z/m)
        raise TypeCastError, "Invalid Enum definition: #{type_string}" unless match

        enum_args = match[1]

        possible_values = []
        value_to_int = {}
        int_to_value = {}

        # Split by comma, but need to handle escaped quotes
        # Parse each enum entry: 'name' = value or 'name'
        entries = parse_enum_entries(enum_args)

        auto_index = 1 # For auto-increment values

        entries.each do |entry|
          name, int_val = parse_enum_entry(entry)
          possible_values << name

          # If no explicit value, use auto-increment
          if int_val.nil?
            int_val = auto_index
            auto_index += 1
          elsif int_val >= auto_index
            auto_index = int_val + 1
          end
          # Update auto_index to be the next number after the highest seen

          value_to_int[name] = int_val
          int_to_value[int_val] = name
        end

        [possible_values, value_to_int, int_to_value]
      end

      # Splits enum entries by comma, handling escaped quotes
      #
      # @param enum_args [String] the enum arguments string
      # @return [Array<String>] list of enum entries
      def parse_enum_entries(enum_args)
        entries = []
        current_entry = +""
        in_quotes = false
        i = 0

        while i < enum_args.length
          char = enum_args[i]

          if char == "'" && (i.zero? || enum_args[i - 1] != "\\")
            in_quotes = !in_quotes
            current_entry += char
          elsif char == "," && !in_quotes
            entries << current_entry.strip
            current_entry = +""
          else
            current_entry += char
          end

          i += 1
        end

        entries << current_entry.strip if current_entry.strip.length.positive?
        entries
      end

      # Parses a single enum entry
      #
      # @param entry [String] e.g., "'active' = 1", "'value'", or "active" (from parser)
      # @return [Array<String, Integer>] [name, integer_value]
      def parse_enum_entry(entry)
        entry = entry.strip

        # Check if it has explicit assignment: 'name' = value or name = value (from parser)
        if entry.include?("=")
          parts = entry.split("=", 2)
          name_part = parts[0].strip
          value_part = parts[1].strip

          # Extract name - might be quoted or unquoted
          name = if name_part.start_with?("'") && name_part.end_with?("'")
                   extract_quoted_string(name_part)
                 else
                   # Already unquoted (from parser)
                   name_part
                 end

          # Parse integer value
          int_val = value_part.to_i

          [name, int_val]
        else
          # Auto-increment: just 'name' or name (from parser)
          name = if entry.start_with?("'") && entry.end_with?("'")
                   extract_quoted_string(entry)
                 else
                   # Already unquoted (from parser)
                   entry
                 end
          # Will assign index + 1 later
          [name, nil]
        end
      end

      # Extracts a string value from quotes, handling escapes
      #
      # @param quoted_str [String] e.g., "'hello'" or "'it\\'s'"
      # @return [String] the unquoted string with escapes processed
      def extract_quoted_string(quoted_str)
        quoted_str = quoted_str.strip
        # Remove surrounding quotes
        unless quoted_str.start_with?("'") && quoted_str.end_with?("'")
          raise TypeCastError, "Invalid enum value format: #{quoted_str}"
        end

        # Remove quotes
        unquoted = quoted_str[1...-1]
        # Unescape single quotes
        unquoted.gsub("\\'", "'")
      end

      # Validates that a string value is a valid enum value
      #
      # @param value [String] the value to validate
      # @raise [TypeCastError] if value is not valid
      def validate_string_value!(value)
        return if @possible_values.include?(value)

        raise TypeCastError.new(
          "Unknown enum value '#{value}'. Valid values: #{@possible_values.join(", ")}",
          from_type: "String",
          to_type: to_s,
          value: value,
        )
      end

      # Validates that an integer value maps to a valid enum value
      #
      # @param value [Integer] the value to validate
      # @raise [TypeCastError] if value is not valid
      def validate_int_value!(value)
        return if @int_to_value.key?(value)

        raise TypeCastError.new(
          "Unknown enum integer #{value}. Valid integers: #{@int_to_value.keys.join(", ")}",
          from_type: "Integer",
          to_type: to_s,
          value: value,
        )
      end
    end
  end
end
