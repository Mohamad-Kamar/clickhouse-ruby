# frozen_string_literal: true

require_relative "clickhouse_ruby/version"
require_relative "clickhouse_ruby/errors"
require_relative "clickhouse_ruby/configuration"
require_relative "clickhouse_ruby/types"
require_relative "clickhouse_ruby/result"
require_relative "clickhouse_ruby/retry_handler"
require_relative "clickhouse_ruby/streaming_result"
require_relative "clickhouse_ruby/client"
require_relative "clickhouse_ruby/connection"
require_relative "clickhouse_ruby/connection_pool"

# ClickhouseRuby - Ruby/ActiveRecord integration for ClickHouse
#
# A robust, reliable ClickHouse client for Ruby that prioritizes:
# - No silent failures (proper error handling)
# - Correct type handling (AST-based parser for complex types)
# - Performance (bulk operations, connection pooling)
# - Security (SSL verification enabled by default)
#
# @example Basic usage
#   ClickhouseRuby.configure do |config|
#     config.host = 'localhost'
#     config.port = 8123
#     config.database = 'analytics'
#   end
#
#   client = ClickhouseRuby::Client.new
#   result = client.execute('SELECT * FROM events LIMIT 10')
#   result.each { |row| puts row['name'] }
#
# @example Bulk insert
#   client.insert('events', [
#     { id: 1, name: 'click', timestamp: Time.now },
#     { id: 2, name: 'view', timestamp: Time.now }
#   ])
#
module ClickhouseRuby
  class << self
    # Returns the global configuration instance
    #
    # @return [Configuration] the configuration object
    def configuration
      @configuration ||= Configuration.new
    end

    # Allows configuration via a block
    #
    # @yield [Configuration] the configuration object
    # @return [Configuration] the configuration object
    #
    # @example
    #   ClickhouseRuby.configure do |config|
    #     config.host = 'clickhouse.example.com'
    #     config.port = 8443
    #     config.ssl = true
    #   end
    def configure
      yield(configuration)
      configuration
    end

    # Resets the configuration to defaults
    # Primarily useful for testing
    #
    # @return [Configuration] a new configuration object
    def reset_configuration!
      @configuration = Configuration.new
    end

    # Creates a new client with the global configuration
    #
    # @return [Client] a new client instance
    def client
      Client.new(configuration)
    end

    # Convenience method to execute a query using global configuration
    #
    # @param sql [String] the SQL query to execute
    # @param options [Hash] query options
    # @return [Result] the query result
    def execute(sql, **options)
      client.execute(sql, **options)
    end

    # Convenience method to insert data using global configuration
    #
    # @param table [String] the table name
    # @param rows [Array<Hash>] the rows to insert
    # @param options [Hash] insert options
    # @return [Result] the insert result
    def insert(table, rows, **options)
      client.insert(table, rows, **options)
    end
  end
end

# Load ActiveRecord integration if ActiveRecord is available
require_relative "clickhouse_ruby/active_record" if defined?(ActiveRecord)
