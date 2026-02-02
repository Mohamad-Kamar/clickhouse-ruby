# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Base class for all ClickHouse types
    #
    # Provides the interface for type conversion between Ruby and ClickHouse.
    # Subclasses implement specific conversion logic.
    #
    # @abstract Subclasses should override {#cast}, {#deserialize}, and {#serialize}
    #
    class Base
      # @return [String] the ClickHouse type name
      attr_reader :name

      # @param name [String] the ClickHouse type name
      def initialize(name)
        @name = name
      end

      # Converts a Ruby value to the appropriate type for this ClickHouse column
      #
      # @param value [Object] the value to convert
      # @return [Object] the converted value
      def cast(value)
        value
      end

      # Converts a value from ClickHouse response format to Ruby
      #
      # @param value [Object] the value from ClickHouse
      # @return [Object] the Ruby value
      def deserialize(value)
        value
      end

      # Converts a Ruby value to ClickHouse SQL literal format
      #
      # @param value [Object] the Ruby value
      # @return [String] the SQL literal
      def serialize(value)
        value.to_s
      end

      # Returns whether NULL values are allowed
      #
      # @return [Boolean] true if nullable
      def nullable?
        false
      end

      # Returns the ClickHouse type string
      #
      # @return [String] the type string
      def to_s
        name
      end

      # Equality comparison
      #
      # @param other [Base] another type
      # @return [Boolean] true if equal
      def ==(other)
        other.is_a?(Base) && other.name == name
      end

      alias eql? ==

      # Hash code for use in hash keys
      #
      # @return [Integer] the hash code
      def hash
        name.hash
      end

      protected

      # Raises a TypeCastError for unsupported type conversion
      #
      # @param value [Object] the value that could not be cast
      # @param message [String, nil] optional custom message
      # @raise [TypeCastError] always
      def raise_cast_error(value, message = nil)
        msg = message || "Cannot cast #{value.class} to #{name}"
        raise TypeCastError.new(
          msg,
          from_type: value.class.name,
          to_type: name,
          value: value,
        )
      end

      # Raises a TypeCastError for invalid string format
      #
      # @param value [String] the invalid string
      # @param format_name [String] description of expected format
      # @raise [TypeCastError] always
      def raise_format_error(value, format_name)
        raise TypeCastError.new(
          "Invalid #{format_name} format: '#{value}'",
          from_type: "String",
          to_type: name,
          value: value,
        )
      end

      # Raises a TypeCastError for empty string input
      #
      # @param value [String] the empty string
      # @raise [TypeCastError] always
      def raise_empty_string_error(value)
        raise TypeCastError.new(
          "Cannot cast empty string to #{name}",
          from_type: "String",
          to_type: name,
          value: value,
        )
      end

      # Raises a TypeCastError for value out of range
      #
      # @param value [Numeric] the out-of-range value
      # @param min [Numeric] minimum allowed value
      # @param max [Numeric] maximum allowed value
      # @raise [TypeCastError] always
      def raise_range_error(value, min, max)
        raise TypeCastError.new(
          "Value #{value} is out of range for #{name} (#{min}..#{max})",
          from_type: value.class.name,
          to_type: name,
          value: value,
        )
      end
    end
  end
end
