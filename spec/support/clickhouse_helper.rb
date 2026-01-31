# frozen_string_literal: true

# Helper module for integration tests with ClickHouse
#
# Provides utilities for:
# - Setting up and tearing down test databases
# - Creating and managing test tables
# - Truncating tables between tests
#
module ClickhouseHelper
  TEST_DATABASE = 'clickhouse_ruby_test'

  class << self
    # Returns a configured client for testing
    #
    # @return [ClickhouseRuby::Client] a test client
    def client
      @client ||= begin
        ClickhouseRuby.configure do |config|
          config.host = ENV.fetch('CLICKHOUSE_HOST', 'localhost')
          config.port = ENV.fetch('CLICKHOUSE_PORT', 8123).to_i
          config.database = TEST_DATABASE
          config.username = ENV.fetch('CLICKHOUSE_USER', 'default')
          config.password = ENV.fetch('CLICKHOUSE_PASSWORD', nil)
          config.ssl = ENV.fetch('CLICKHOUSE_SSL', 'false') == 'true'
          config.connect_timeout = 5
          config.read_timeout = 30
        end
        ClickhouseRuby.client
      end
    end

    # Sets up the test database
    # Creates the database if it doesn't exist
    def setup_test_database
      puts "Setting up test database: #{TEST_DATABASE}"

      # Create database using system database first
      system_client = create_system_client
      system_client.execute("CREATE DATABASE IF NOT EXISTS #{TEST_DATABASE}")

      # Create common test tables
      create_test_tables

      puts "Test database setup complete"
    rescue StandardError => e
      puts "Warning: Could not setup test database: #{e.message}"
      puts "Integration tests may fail"
    end

    # Tears down the test database
    # Drops all test tables and optionally the database
    def teardown_test_database
      puts "Tearing down test database: #{TEST_DATABASE}"

      if ENV['CLICKHOUSE_DROP_TEST_DB'] == 'true'
        system_client = create_system_client
        system_client.execute("DROP DATABASE IF EXISTS #{TEST_DATABASE}")
      else
        # Just drop tables, keep database
        drop_test_tables
      end

      puts "Test database teardown complete"
    rescue StandardError => e
      puts "Warning: Could not teardown test database: #{e.message}"
    end

    # Truncates all test tables
    # Call this between tests to ensure isolation
    def truncate_tables
      TEST_TABLES.each do |table_name, _|
        client.execute("TRUNCATE TABLE IF EXISTS #{table_name}")
      end
    end

    # Creates a test table with the given schema
    #
    # @param name [String] table name
    # @param schema [String] column definitions
    # @param engine [String] table engine (default: MergeTree)
    # @param order_by [String] ORDER BY clause
    def create_table(name, schema, engine: 'MergeTree', order_by: 'tuple()')
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{name} (
          #{schema}
        ) ENGINE = #{engine}
        ORDER BY #{order_by}
      SQL
    end

    # Drops a test table
    #
    # @param name [String] table name
    def drop_table(name)
      client.execute("DROP TABLE IF EXISTS #{name}")
    end

    # Inserts test data into a table
    #
    # @param table [String] table name
    # @param rows [Array<Hash>] data rows
    def insert_data(table, rows)
      client.insert(table, rows)
    end

    private

    # Creates a client connected to the system database
    def create_system_client
      config = ClickhouseRuby::Configuration.new
      config.host = ENV.fetch('CLICKHOUSE_HOST', 'localhost')
      config.port = ENV.fetch('CLICKHOUSE_PORT', 8123).to_i
      config.database = 'system'
      config.username = ENV.fetch('CLICKHOUSE_USER', 'default')
      config.password = ENV.fetch('CLICKHOUSE_PASSWORD', nil)
      config.ssl = ENV.fetch('CLICKHOUSE_SSL', 'false') == 'true'
      ClickhouseRuby::Client.new(config)
    end

    # Standard test tables used across integration tests
    TEST_TABLES = {
      'test_integers' => {
        schema: <<~SQL,
          id UInt64,
          int8_col Int8,
          int16_col Int16,
          int32_col Int32,
          int64_col Int64,
          uint8_col UInt8,
          uint16_col UInt16,
          uint32_col UInt32,
          uint64_col UInt64
        SQL
        order_by: 'id'
      },
      'test_strings' => {
        schema: <<~SQL,
          id UInt64,
          name String,
          fixed_name FixedString(10),
          nullable_name Nullable(String)
        SQL
        order_by: 'id'
      },
      'test_arrays' => {
        schema: <<~SQL,
          id UInt64,
          int_array Array(Int32),
          string_array Array(String),
          nested_array Array(Array(Int32))
        SQL
        order_by: 'id'
      },
      'test_complex' => {
        schema: <<~SQL,
          id UInt64,
          tuple_col Tuple(String, UInt64),
          map_col Map(String, Int32),
          nullable_int Nullable(Int32),
          array_tuple Array(Tuple(String, UInt64))
        SQL
        order_by: 'id'
      },
      'test_events' => {
        schema: <<~SQL,
          id UInt64,
          event_type String,
          user_id UInt64,
          timestamp DateTime,
          metadata Map(String, String),
          created_at DateTime DEFAULT now()
        SQL
        order_by: '(event_type, timestamp)'
      }
    }.freeze

    def create_test_tables
      TEST_TABLES.each do |name, config|
        create_table(name, config[:schema], order_by: config[:order_by])
      end
    end

    def drop_test_tables
      TEST_TABLES.each_key do |name|
        drop_table(name)
      end
    end
  end
end

# RSpec shared context for integration tests
RSpec.shared_context 'integration test', integration: true do
  let(:client) { ClickhouseHelper.client }

  before(:each) do
    ClickhouseHelper.truncate_tables
  end
end

# Shared examples for error handling
RSpec.shared_examples 'raises on query error' do |error_class|
  it "raises #{error_class}" do
    expect { subject }.to raise_error(error_class)
  end
end

RSpec.shared_examples 'does not silently fail' do
  it 'raises an exception instead of returning silently' do
    expect { subject }.to raise_error(ClickhouseRuby::Error)
  end
end
