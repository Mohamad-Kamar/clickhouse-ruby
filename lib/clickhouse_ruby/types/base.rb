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
    end
  end
end
