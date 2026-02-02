# frozen_string_literal: true

require "time"
require "date"

module ClickhouseRuby
  module Types
    # Type handler for ClickHouse date and datetime types
    #
    # Handles: Date, Date32, DateTime, DateTime64
    #
    # Date types:
    # - Date: days since 1970-01-01 (range: 1970-01-01 to 2149-06-06)
    # - Date32: days since 1970-01-01 (range: 1900-01-01 to 2299-12-31)
    #
    # DateTime types:
    # - DateTime: seconds since 1970-01-01 00:00:00 UTC
    # - DateTime64(precision): with sub-second precision (0-9 decimal places)
    #
    class DateTime < Base
      # The precision for DateTime64 (nil for other types)
      # @return [Integer, nil] precision in decimal places
      attr_reader :precision

      # The timezone for DateTime types
      # @return [String, nil] timezone name
      attr_reader :timezone

      def initialize(name, precision: nil, timezone: nil)
        super(name)
        @precision = precision
        @timezone = timezone
      end

      # Converts a Ruby value to a Time or Date
      #
      # @param value [Object] the value to convert
      # @return [Time, Date, nil] the time/date value
      # @raise [TypeCastError] if the value cannot be converted
      def cast(value)
        return nil if value.nil?

        case value
        when ::Time
          date_only? ? value.to_date : value
        when ::Date
          date_only? ? value : value.to_time
        when ::String
          parse_string(value)
        when ::Integer
          # Unix timestamp
          date_only? ? Time.at(value).to_date : Time.at(value)
        else
          raise_cast_error(value)
        end
      end

      # Converts a value from ClickHouse to Ruby Time or Date
      #
      # @param value [Object] the value from ClickHouse
      # @return [Time, Date, nil] the time/date value
      def deserialize(value)
        return nil if value.nil?

        case value
        when ::Time, ::Date
          date_only? ? value.to_date : value.to_time
        when ::String
          parse_string(value)
        when ::Integer
          date_only? ? Time.at(value).to_date : Time.at(value)
        else
          parse_string(value.to_s)
        end
      end

      # Converts a time/date to SQL literal
      #
      # @param value [Time, Date, nil] the value to serialize
      # @return [String] the SQL literal
      def serialize(value)
        return "NULL" if value.nil?

        if date_only?
          format_date(value)
        else
          format_datetime(value)
        end
      end

      # Returns whether this is a date-only type (Date, Date32)
      #
      # @return [Boolean] true if date-only
      def date_only?
        name.start_with?("Date") && !name.start_with?("DateTime")
      end

      private

      # Parses a string to a Time or Date
      #
      # @param value [String] the string to parse
      # @return [Time, Date] the parsed value
      # @raise [TypeCastError] if the string cannot be parsed
      def parse_string(value)
        stripped = value.strip

        raise_empty_string_error(value) if stripped.empty?

        if date_only?
          ::Date.parse(stripped)
        else
          ::Time.parse(stripped)
        end
      rescue ArgumentError => e
        raise_cast_error(value, "Cannot cast '#{value}' to #{name}: #{e.message}")
      end

      # Formats a date value for SQL
      #
      # @param value [Date, Time] the value to format
      # @return [String] the formatted SQL literal
      def format_date(value)
        date = value.respond_to?(:to_date) ? value.to_date : value
        "'#{date.strftime("%Y-%m-%d")}'"
      end

      # Formats a datetime value for SQL
      #
      # @param value [Time, Date] the value to format
      # @return [String] the formatted SQL literal
      def format_datetime(value)
        time = value.respond_to?(:to_time) ? value.to_time : value

        if @precision&.positive?
          # DateTime64 with fractional seconds
          format_str = "%Y-%m-%d %H:%M:%S.%#{@precision}N"
          "'#{time.strftime(format_str)}'"
        else
          # Regular DateTime
          "'#{time.strftime("%Y-%m-%d %H:%M:%S")}'"
        end
      end
    end
  end
end
