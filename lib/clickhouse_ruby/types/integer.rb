# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse integer types
    #
    # Handles: Int8, Int16, Int32, Int64, Int128, Int256
    #          UInt8, UInt16, UInt32, UInt64, UInt128, UInt256
    #
    # ClickHouse integers are exact - no floating point issues.
    # Large integers (128, 256 bit) use Ruby's BigInteger.
    #
    class Integer < Base
      # Size limits for each integer type
      LIMITS = {
        'Int8' => { min: -128, max: 127 },
        'Int16' => { min: -32_768, max: 32_767 },
        'Int32' => { min: -2_147_483_648, max: 2_147_483_647 },
        'Int64' => { min: -9_223_372_036_854_775_808, max: 9_223_372_036_854_775_807 },
        'Int128' => { min: -(2**127), max: (2**127) - 1 },
        'Int256' => { min: -(2**255), max: (2**255) - 1 },
        'UInt8' => { min: 0, max: 255 },
        'UInt16' => { min: 0, max: 65_535 },
        'UInt32' => { min: 0, max: 4_294_967_295 },
        'UInt64' => { min: 0, max: 18_446_744_073_709_551_615 },
        'UInt128' => { min: 0, max: (2**128) - 1 },
        'UInt256' => { min: 0, max: (2**256) - 1 }
      }.freeze

      # Converts a Ruby value to an integer
      #
      # @param value [Object] the value to convert
      # @return [Integer, nil] the integer value
      # @raise [TypeCastError] if the value cannot be converted
      def cast(value)
        return nil if value.nil?

        case value
        when ::Integer
          validate_range!(value)
          value
        when ::Float
          int_value = value.to_i
          validate_range!(int_value)
          int_value
        when ::String
          int_value = parse_string(value)
          validate_range!(int_value)
          int_value
        when true
          1
        when false
          0
        else
          raise TypeCastError.new(
            "Cannot cast #{value.class} to #{name}",
            from_type: value.class.name,
            to_type: name,
            value: value
          )
        end
      end

      # Converts a value from ClickHouse to Ruby Integer
      #
      # @param value [Object] the value from ClickHouse
      # @return [Integer, nil] the integer value
      def deserialize(value)
        return nil if value.nil?

        case value
        when ::Integer
          value
        when ::String
          parse_string(value)
        when ::Float
          value.to_i
        else
          value.to_i
        end
      end

      # Converts an integer to SQL literal
      #
      # @param value [Integer, nil] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return 'NULL' if value.nil?

        value.to_s
      end

      # Returns whether this is an unsigned integer type
      #
      # @return [Boolean] true if unsigned
      def unsigned?
        name.start_with?('U')
      end

      # Returns the bit size of this integer type
      #
      # @return [Integer] the bit size (8, 16, 32, 64, 128, or 256)
      def bit_size
        name.gsub(/[^0-9]/, '').to_i
      end

      private

      # Parses a string to an integer
      #
      # @param value [String] the string to parse
      # @return [Integer] the parsed integer
      # @raise [TypeCastError] if the string is not a valid integer
      def parse_string(value)
        stripped = value.strip

        # Handle empty strings
        if stripped.empty?
          raise TypeCastError.new(
            "Cannot cast empty string to #{name}",
            from_type: 'String',
            to_type: name,
            value: value
          )
        end

        # Use Integer() for strict parsing
        Integer(stripped)
      rescue ArgumentError
        raise TypeCastError.new(
          "Cannot cast '#{value}' to #{name}",
          from_type: 'String',
          to_type: name,
          value: value
        )
      end

      # Validates that a value is within the type's range
      #
      # @param value [Integer] the value to validate
      # @raise [TypeCastError] if the value is out of range
      def validate_range!(value)
        limits = LIMITS[name]
        return unless limits  # Unknown type, skip validation

        if value < limits[:min] || value > limits[:max]
          raise TypeCastError.new(
            "Value #{value} is out of range for #{name} (#{limits[:min]}..#{limits[:max]})",
            from_type: value.class.name,
            to_type: name,
            value: value
          )
        end
      end
    end
  end
end
