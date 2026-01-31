# frozen_string_literal: true

module ClickhouseRuby
  # Base error class for all ClickhouseRuby errors
  # All errors include context information to aid debugging
  class Error < StandardError
    # @return [Exception, nil] the original exception that caused this error
    attr_reader :original_error

    # @param message [String] the error message
    # @param original_error [Exception, nil] the underlying exception
    def initialize(message = nil, original_error: nil)
      @original_error = original_error
      super(message)
    end
  end

  # Connection-related errors
  # Raised when there are issues establishing or maintaining a connection
  class ConnectionError < Error; end

  # Raised when a connection cannot be established
  # Common causes: wrong host/port, network issues, authentication failure
  class ConnectionNotEstablished < ConnectionError; end

  # Raised when a connection or query times out
  class ConnectionTimeout < ConnectionError; end

  # Raised for SSL/TLS related errors
  # Common causes: certificate verification failure, SSL protocol mismatch
  class SSLError < ConnectionError; end

  # Query execution errors
  # Raised when there are issues executing a query
  class QueryError < Error
    # @return [Integer, nil] ClickHouse error code
    attr_reader :code

    # @return [String, nil] HTTP status code from the response
    attr_reader :http_status

    # @return [String, nil] the SQL that caused the error
    attr_reader :sql

    # @param message [String] the error message
    # @param code [Integer, nil] ClickHouse error code
    # @param http_status [String, nil] HTTP response status
    # @param sql [String, nil] the SQL query that failed
    # @param original_error [Exception, nil] the underlying exception
    def initialize(message = nil, code: nil, http_status: nil, sql: nil, original_error: nil)
      @code = code
      @http_status = http_status
      @sql = sql
      super(message, original_error: original_error)
    end

    # Returns a detailed error message including context
    #
    # @return [String] the detailed error message
    def detailed_message
      parts = [message]
      parts << "Code: #{code}" if code
      parts << "HTTP Status: #{http_status}" if http_status
      parts << "SQL: #{sql}" if sql
      parts.join(' | ')
    end
  end

  # Raised for SQL syntax errors
  class SyntaxError < QueryError; end

  # Raised when a query is invalid (e.g., unknown table, column)
  class StatementInvalid < QueryError; end

  # Raised when a query exceeds its time limit
  class QueryTimeout < QueryError; end

  # Raised when a table doesn't exist
  class UnknownTable < QueryError; end

  # Raised when a column doesn't exist
  class UnknownColumn < QueryError; end

  # Raised when a database doesn't exist
  class UnknownDatabase < QueryError; end

  # Type conversion errors
  # Raised when there are issues converting between Ruby and ClickHouse types
  class TypeCastError < Error
    # @return [String, nil] the source type
    attr_reader :from_type

    # @return [String, nil] the target type
    attr_reader :to_type

    # @return [Object, nil] the value that couldn't be converted
    attr_reader :value

    # @param message [String] the error message
    # @param from_type [String, nil] the source type
    # @param to_type [String, nil] the target type
    # @param value [Object, nil] the value that failed conversion
    def initialize(message = nil, from_type: nil, to_type: nil, value: nil)
      @from_type = from_type
      @to_type = to_type
      @value = value
      super(message)
    end
  end

  # Configuration errors
  # Raised when there are issues with configuration
  class ConfigurationError < Error; end

  # Pool errors
  # Raised when there are issues with the connection pool
  class PoolError < Error; end

  # Raised when no connections are available in the pool
  class PoolExhausted < PoolError; end

  # Raised when waiting for a connection times out
  class PoolTimeout < PoolError; end

  # Maps ClickHouse error codes to exception classes
  # See: https://github.com/ClickHouse/ClickHouse/blob/master/src/Common/ErrorCodes.cpp
  ERROR_CODE_MAPPING = {
    60 => UnknownTable,        # UNKNOWN_TABLE
    16 => UnknownColumn,       # NO_SUCH_COLUMN_IN_TABLE
    81 => UnknownDatabase,     # UNKNOWN_DATABASE
    62 => SyntaxError,         # SYNTAX_ERROR
    159 => QueryTimeout,       # TIMEOUT_EXCEEDED
  }.freeze

  class << self
    # Maps a ClickHouse error code to the appropriate exception class
    #
    # @param code [Integer] the ClickHouse error code
    # @return [Class] the exception class to use
    def error_class_for_code(code)
      ERROR_CODE_MAPPING.fetch(code, QueryError)
    end
  end
end
