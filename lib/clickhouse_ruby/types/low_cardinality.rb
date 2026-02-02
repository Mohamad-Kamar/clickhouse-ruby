# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse LowCardinality type
    #
    # LowCardinality is an optimization wrapper that stores string values
    # in a dictionary for better compression and performance.
    #
    # @example
    #   type = LowCardinality.new('LowCardinality', element_type: String.new('String'))
    #   type.cast('hello')
    #   type.serialize('hello') # => "'hello'"
    #
    class LowCardinality < Base
      # @return [Base] the wrapped type
      attr_reader :element_type

      # @param name [String] the type name
      # @param element_type [Base] the wrapped type
      def initialize(name, element_type: nil)
        super(name)
        @element_type = element_type || Base.new("String")
      end

      # Converts a Ruby value using the wrapped type
      #
      # @param value [Object] the value to convert
      # @return [Object] the converted value
      def cast(value)
        @element_type.cast(value)
      end

      # Converts a value from ClickHouse using the wrapped type
      #
      # @param value [Object] the value from ClickHouse
      # @return [Object] the Ruby value
      def deserialize(value)
        @element_type.deserialize(value)
      end

      # Converts a value to SQL literal using the wrapped type
      #
      # @param value [Object] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        @element_type.serialize(value)
      end

      # Returns the full type string
      #
      # @return [String] the type string
      def to_s
        "LowCardinality(#{@element_type})"
      end
    end
  end
end
