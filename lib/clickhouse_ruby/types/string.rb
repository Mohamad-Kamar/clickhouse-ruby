# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse string types
    #
    # Handles: String, FixedString(N)
    #
    # ClickHouse strings are byte sequences, not necessarily valid UTF-8.
    # However, most usage is with UTF-8 text.
    #
    class String < Base
      # The fixed length for FixedString types
      # @return [Integer, nil] the fixed length or nil for String type
      attr_reader :length

      def initialize(name, length: nil)
        super(name)
        @length = length
      end

      # Converts a Ruby value to a string
      #
      # @param value [Object] the value to convert
      # @return [String, nil] the string value
      def cast(value)
        return nil if value.nil?

        str = value.to_s

        # For FixedString, pad or truncate to length
        if @length
          str = str.ljust(@length, "\0")[0, @length]
        end

        str
      end

      # Converts a value from ClickHouse to Ruby String
      #
      # @param value [Object] the value from ClickHouse
      # @return [String, nil] the string value
      def deserialize(value)
        return nil if value.nil?

        str = value.to_s

        # For FixedString, remove trailing null bytes
        if @length
          str = str.gsub(/\0+\z/, '')
        end

        str
      end

      # Converts a string to SQL literal with proper escaping
      #
      # @param value [String, nil] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return 'NULL' if value.nil?

        escaped = escape_string(value.to_s)
        "'#{escaped}'"
      end

      private

      # Escapes a string for use in ClickHouse SQL
      #
      # @param value [String] the string to escape
      # @return [String] the escaped string
      def escape_string(value)
        value.gsub("\\", "\\\\")
             .gsub("'", "\\'")
             .gsub("\n", "\\n")
             .gsub("\r", "\\r")
             .gsub("\t", "\\t")
             .gsub("\0", "\\0")
      end
    end
  end
end
