# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse Bool type
    #
    # ClickHouse Bool is internally stored as UInt8 (0 or 1)
    # but can accept various truthy/falsy values.
    #
    class Boolean < Base
      include NullSafe

      # Values that represent true
      TRUE_VALUES = [true, 1, "1", "true", "TRUE", "True", "t", "T", "yes", "YES", "Yes", "y", "Y", "on", "ON",
                     "On",].freeze

      # Values that represent false
      FALSE_VALUES = [false, 0, "0", "false", "FALSE", "False", "f", "F", "no", "NO", "No", "n", "N", "off", "OFF",
                      "Off",].freeze

      protected

      # Converts a Ruby value to a boolean
      #
      # @param value [Object] the value to convert (guaranteed non-nil)
      # @return [Boolean] the boolean value
      # @raise [TypeCastError] if the value cannot be interpreted as boolean
      def cast_value(value)
        if TRUE_VALUES.include?(value)
          true
        elsif FALSE_VALUES.include?(value)
          false
        else
          raise_cast_error(value, "Cannot cast '#{value}' to Bool")
        end
      end

      # Converts a value from ClickHouse to Ruby boolean
      #
      # @param value [Object] the value from ClickHouse (guaranteed non-nil)
      # @return [Boolean] the boolean value
      def deserialize_value(value)
        case value
        when true, 1, "1", "true"
          true
        when false, 0, "0", "false"
          false
        else
          # Default to truthy evaluation
          !!value
        end
      end

      # Converts a boolean to SQL literal
      #
      # @param value [Boolean] the value to serialize (guaranteed non-nil)
      # @return [String] the SQL literal (1 or 0)
      def serialize_value(value)
        # Check explicit FALSE_VALUES first since Ruby's 0 is truthy
        if FALSE_VALUES.include?(value)
          "0"
        elsif TRUE_VALUES.include?(value)
          "1"
        else
          # Default to truthy evaluation for other values
          value ? "1" : "0"
        end
      end
    end
  end
end
