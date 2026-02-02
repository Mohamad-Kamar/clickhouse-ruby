# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse Decimal types
    #
    # Handles: Decimal(P, S), Decimal32(S), Decimal64(S), Decimal128(S), Decimal256(S)
    #
    # Uses BigDecimal for arbitrary precision arithmetic to avoid floating point errors.
    # Validates precision and scale according to ClickHouse constraints.
    #
    class Decimal < Base
      # Precision limits for each Decimal variant
      PRECISION_LIMITS = {
        32 => 9,
        64 => 18,
        128 => 38,
        256 => 76,
      }.freeze

      # @return [Integer] the precision (total number of significant digits)
      attr_reader :precision

      # @return [Integer] the scale (number of digits after decimal point)
      attr_reader :scale

      # Initializes a Decimal type
      #
      # @param name [String] the ClickHouse type name (e.g., 'Decimal(18, 4)')
      # @param precision [Integer, nil] optional precision override
      # @param scale [Integer, nil] optional scale override
      # @param arg_types [Array, nil] optional parsed argument types (ignored for Decimal)
      # @raise [ConfigurationError] if precision/scale are invalid
      def initialize(name, precision: nil, scale: nil, arg_types: nil)
        super(name)
        @precision, @scale = parse_decimal_params(name, precision, scale)
        validate_params!
      end

      # Converts a Ruby value to BigDecimal
      #
      # @param value [Object] the value to convert
      # @return [BigDecimal, nil] the BigDecimal value
      # @raise [TypeCastError] if the value cannot be converted
      def cast(value)
        return nil if value.nil?

        bd = case value
             when ::BigDecimal
               value
             when ::Integer
               BigDecimal(value)
             when ::Float
               BigDecimal(value.to_s)
             when ::String
               BigDecimal(value)
             else
               raise TypeCastError.new(
                 "Cannot cast #{value.class} to #{name}",
                 from_type: value.class.name,
                 to_type: name,
                 value: value,
               )
             end

        validate_value!(bd)
        bd
      end

      # Converts a value from ClickHouse response to Ruby BigDecimal
      #
      # @param value [Object] the value from ClickHouse
      # @return [BigDecimal, nil] the BigDecimal value
      def deserialize(value)
        return nil if value.nil?

        BigDecimal(value.to_s)
      end

      # Converts a BigDecimal to ClickHouse SQL literal
      #
      # @param value [BigDecimal, nil] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return "NULL" if value.nil?

        bd = cast(value)
        # Use 'F' format to preserve precision (fixed-point notation)
        bd.to_s("F")
      end

      # Returns the internal ClickHouse type based on precision
      #
      # @return [Symbol] the internal type (:Decimal32, :Decimal64, :Decimal128, or :Decimal256)
      def internal_type
        case precision
        when 1..9
          :Decimal32
        when 10..18
          :Decimal64
        when 19..38
          :Decimal128
        when 39..76
          :Decimal256
        end
      end

      private

      # Parses precision and scale from type string
      #
      # Handles:
      # - Decimal(18, 4) → precision=18, scale=4
      # - Decimal64(4) → precision=max_for_variant, scale=4
      #
      # @param name [String] the type string
      # @param precision [Integer, nil] optional override
      # @param scale [Integer, nil] optional override
      # @return [Array<Integer>] [precision, scale]
      def parse_decimal_params(name, precision, scale)
        # Match: Decimal(P, S) or Decimal32(S), Decimal64(S), etc.
        # Allow negative numbers to be parsed (for proper error reporting)
        if name =~ /^Decimal(\d{2,3})?\((-?\d+)(?:,\s*(-?\d+))?\)$/
          variant = Regexp.last_match(1)&.to_i
          first_arg = Regexp.last_match(2).to_i
          second_arg = Regexp.last_match(3)&.to_i

          if variant
            # Decimal32(4) → variant determines precision, first_arg is scale
            max_p = PRECISION_LIMITS[variant]
            [max_p, first_arg]
          else
            # Decimal(18, 4) → first_arg is precision, second_arg is scale
            second_arg ||= 0
            [first_arg, second_arg]
          end
        else
          # Fallback to parameters or defaults
          [precision || 10, scale || 0]
        end
      end

      # Validates that precision and scale parameters are valid
      #
      # @raise [ConfigurationError] if validation fails
      def validate_params!
        unless (1..76).include?(@precision)
          raise ConfigurationError, "Decimal precision must be 1-76, got #{@precision}"
        end

        return if (0..@precision).include?(@scale)

        raise ConfigurationError, "Decimal scale must be 0-#{@precision}, got #{@scale}"
      end

      # Validates that a BigDecimal value doesn't exceed type limits
      #
      # @param bd [BigDecimal] the value to validate
      # @raise [TypeCastError] if the value exceeds limits
      def validate_value!(bd)
        # Check integer part doesn't exceed allowed digits
        max_integer_digits = @precision - @scale

        # Use 'F' format to get fixed-point notation
        bd_str = bd.to_s("F")
        # Split on decimal point to get integer and fractional parts
        parts = bd_str.split(".")
        integer_part = parts[0].gsub(/[^0-9]/, "") # Remove sign
        # Remove leading zeros
        integer_digits = integer_part.sub(/^0+/, "") || "0"

        return unless integer_digits.length > max_integer_digits

        raise TypeCastError.new(
          "Value #{bd} exceeds maximum integer digits (#{max_integer_digits}) for #{name}",
          from_type: "BigDecimal",
          to_type: name,
          value: bd,
        )
      end
    end
  end
end
