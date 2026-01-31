# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse Bool type
    #
    # ClickHouse Bool is internally stored as UInt8 (0 or 1)
    # but can accept various truthy/falsy values.
    #
    class Boolean < Base
      # Values that represent true
      TRUE_VALUES = [true, 1, '1', 'true', 'TRUE', 'True', 't', 'T', 'yes', 'YES', 'Yes', 'y', 'Y', 'on', 'ON', 'On'].freeze

      # Values that represent false
      FALSE_VALUES = [false, 0, '0', 'false', 'FALSE', 'False', 'f', 'F', 'no', 'NO', 'No', 'n', 'N', 'off', 'OFF', 'Off'].freeze

      # Converts a Ruby value to a boolean
      #
      # @param value [Object] the value to convert
      # @return [Boolean, nil] the boolean value
      # @raise [TypeCastError] if the value cannot be interpreted as boolean
      def cast(value)
        return nil if value.nil?

        if TRUE_VALUES.include?(value)
          true
        elsif FALSE_VALUES.include?(value)
          false
        else
          raise TypeCastError.new(
            "Cannot cast '#{value}' to Bool",
            from_type: value.class.name,
            to_type: name,
            value: value
          )
        end
      end

      # Converts a value from ClickHouse to Ruby boolean
      #
      # @param value [Object] the value from ClickHouse
      # @return [Boolean, nil] the boolean value
      def deserialize(value)
        return nil if value.nil?

        case value
        when true, 1, '1', 'true'
          true
        when false, 0, '0', 'false'
          false
        else
          # Default to truthy evaluation
          !!value
        end
      end

      # Converts a boolean to SQL literal
      #
      # @param value [Boolean, nil] the value to serialize
      # @return [String] the SQL literal (1 or 0)
      def serialize(value)
        return 'NULL' if value.nil?

        # Check explicit FALSE_VALUES first since Ruby's 0 is truthy
        if FALSE_VALUES.include?(value)
          '0'
        elsif TRUE_VALUES.include?(value)
          '1'
        else
          # Default to truthy evaluation for other values
          value ? '1' : '0'
        end
      end
    end
  end
end
