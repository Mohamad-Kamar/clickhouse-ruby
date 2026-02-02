# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse UUID type
    #
    # UUIDs are stored as 16-byte values but represented as strings
    # in the format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    #
    class UUID < Base
      include NullSafe

      # UUID regex pattern
      UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      protected

      # Converts a Ruby value to a UUID string
      #
      # @param value [Object] the value to convert (guaranteed non-nil)
      # @return [String] the UUID string
      # @raise [TypeCastError] if the value is not a valid UUID
      def cast_value(value)
        str = normalize_uuid(value)
        validate_uuid!(str, value)
        str
      end

      # Converts a value from ClickHouse to a UUID string
      #
      # @param value [Object] the value from ClickHouse (guaranteed non-nil)
      # @return [String] the UUID string
      def deserialize_value(value)
        normalize_uuid(value)
      end

      # Converts a UUID to SQL literal
      #
      # @param value [String] the UUID value (guaranteed non-nil)
      # @return [String] the SQL literal
      def serialize_value(value)
        "'#{normalize_uuid(value)}'"
      end

      private

      # Normalizes a UUID value to the standard format
      #
      # @param value [Object] the value to normalize
      # @return [String] the normalized UUID
      def normalize_uuid(value)
        str = value.to_s.strip.downcase

        # Remove braces if present
        str = str.gsub(/[{}]/, "")

        # If no hyphens, add them
        if str.length == 32 && !str.include?("-")
          str = "#{str[0..7]}-#{str[8..11]}-#{str[12..15]}-#{str[16..19]}-#{str[20..31]}"
        end

        str
      end

      # Validates that a string is a valid UUID
      #
      # @param str [String] the normalized UUID string
      # @param original [Object] the original value (for error messages)
      # @raise [TypeCastError] if invalid
      def validate_uuid!(str, original)
        return if str.match?(UUID_PATTERN)

        raise_format_error(original, "UUID")
      end
    end
  end
end
