# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse Nullable type
    #
    # Nullable wraps another type to allow NULL values.
    # Without Nullable, ClickHouse columns cannot contain NULL.
    #
    # @example
    #   type = Nullable.new('Nullable', element_type: Integer.new('Int32'))
    #   type.cast(nil)   # => nil
    #   type.cast(42)    # => 42
    #   type.nullable?   # => true
    #
    class Nullable < Base
      # @return [Base] the wrapped type
      attr_reader :element_type

      # @param name [String] the type name
      # @param element_type [Base] the wrapped type
      def initialize(name, element_type: nil)
        super(name)
        @element_type = element_type || Base.new("String")
      end

      # Converts a Ruby value, allowing nil
      #
      # @param value [Object] the value to convert
      # @return [Object, nil] the converted value
      def cast(value)
        return nil if value.nil?

        @element_type.cast(value)
      end

      # Converts a value from ClickHouse, allowing nil
      #
      # @param value [Object] the value from ClickHouse
      # @return [Object, nil] the Ruby value
      def deserialize(value)
        return nil if value.nil?
        return nil if value.is_a?(::String) && value == '\\N'

        @element_type.deserialize(value)
      end

      # Converts a value to SQL literal, handling NULL
      #
      # @param value [Object, nil] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return "NULL" if value.nil?

        @element_type.serialize(value)
      end

      # Returns true - this type allows NULL
      #
      # @return [Boolean] true
      def nullable?
        true
      end

      # Returns the full type string
      #
      # @return [String] the type string
      def to_s
        "Nullable(#{@element_type})"
      end
    end
  end
end
