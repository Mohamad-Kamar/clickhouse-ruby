# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Provides automatic null handling for type classes
    #
    # When included, wraps cast, deserialize, and serialize methods
    # to handle nil values automatically. Subclasses implement
    # cast_value, deserialize_value, and serialize_value instead.
    #
    # @example
    #   class Integer < Base
    #     include NullSafe
    #
    #     protected
    #
    #     def cast_value(value)
    #       # value is guaranteed non-nil here
    #       value.to_i
    #     end
    #   end
    #
    module NullSafe
      # Converts a Ruby value, returning nil for nil input
      #
      # @param value [Object] the value to cast
      # @return [Object, nil] the cast value or nil
      def cast(value)
        return nil if value.nil?

        cast_value(value)
      end

      # Deserializes a value from ClickHouse, returning nil for nil input
      #
      # @param value [Object] the value from ClickHouse
      # @return [Object, nil] the deserialized value or nil
      def deserialize(value)
        return nil if value.nil?

        deserialize_value(value)
      end

      # Serializes a value for ClickHouse, returning "NULL" for nil input
      #
      # @param value [Object] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return "NULL" if value.nil?

        serialize_value(value)
      end

      protected

      # Override in subclass - actual casting logic (value guaranteed non-nil)
      #
      # @param value [Object] the non-nil value to cast
      # @return [Object] the cast value
      def cast_value(value)
        value
      end

      # Override in subclass - actual deserialization logic (value guaranteed non-nil)
      #
      # @param value [Object] the non-nil value to deserialize
      # @return [Object] the deserialized value
      def deserialize_value(value)
        value
      end

      # Override in subclass - actual serialization logic (value guaranteed non-nil)
      #
      # @param value [Object] the non-nil value to serialize
      # @return [String] the SQL literal
      def serialize_value(value)
        value.to_s
      end
    end
  end
end
