# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse floating point types
    #
    # Handles: Float32, Float64
    #
    # Note: ClickHouse also supports special values: inf, -inf, nan
    #
    class Float < Base
      # Converts a Ruby value to a float
      #
      # @param value [Object] the value to convert
      # @return [Float, nil] the float value
      # @raise [TypeCastError] if the value cannot be converted
      def cast(value)
        return nil if value.nil?

        case value
        when ::Float
          value
        when ::Integer
          value.to_f
        when ::String
          parse_string(value)
        when ::BigDecimal
          value.to_f
        else
          raise TypeCastError.new(
            "Cannot cast #{value.class} to #{name}",
            from_type: value.class.name,
            to_type: name,
            value: value
          )
        end
      end

      # Converts a value from ClickHouse to Ruby Float
      #
      # @param value [Object] the value from ClickHouse
      # @return [Float, nil] the float value
      def deserialize(value)
        return nil if value.nil?

        case value
        when ::Float
          value
        when ::String
          parse_string(value)
        else
          value.to_f
        end
      end

      # Converts a float to SQL literal
      #
      # @param value [Float, nil] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return 'NULL' if value.nil?

        if value.nan?
          'nan'
        elsif value.infinite? == 1
          'inf'
        elsif value.infinite? == -1
          '-inf'
        else
          value.to_s
        end
      end

      private

      # Parses a string to a float
      #
      # @param value [String] the string to parse
      # @return [Float] the parsed float
      # @raise [TypeCastError] if the string is not a valid float
      def parse_string(value)
        stripped = value.strip.downcase

        # Handle special values
        case stripped
        when 'inf', '+inf', 'infinity', '+infinity'
          ::Float::INFINITY
        when '-inf', '-infinity'
          -::Float::INFINITY
        when 'nan'
          ::Float::NAN
        else
          # Handle empty strings
          if stripped.empty?
            raise TypeCastError.new(
              "Cannot cast empty string to #{name}",
              from_type: 'String',
              to_type: name,
              value: value
            )
          end

          Float(stripped)
        end
      rescue ArgumentError
        raise TypeCastError.new(
          "Cannot cast '#{value}' to #{name}",
          from_type: 'String',
          to_type: name,
          value: value
        )
      end
    end
  end
end
