# frozen_string_literal: true

require "active_record/connection_adapters/abstract_adapter"
require_relative "arel_visitor"
require_relative "schema_statements"
require_relative "relation_extensions"

module ClickhouseRuby
  module ActiveRecord
    # ClickHouse database connection adapter for ActiveRecord
    #
    # This adapter allows Rails applications to use ClickHouse as a database
    # backend through ActiveRecord's standard interface.
    #
    # @note ClickHouse has significant differences from traditional RDBMS:
    #   - No transaction support (commits are immediate)
    #   - DELETE uses ALTER TABLE ... DELETE WHERE syntax
    #   - UPDATE uses ALTER TABLE ... UPDATE ... WHERE syntax
    #   - No foreign key constraints
    #   - No savepoints
    #
    # @example database.yml configuration
    #   development:
    #     adapter: clickhouse
    #     host: localhost
    #     port: 8123
    #     database: analytics
    #     username: default
    #     password: ''
    #     ssl: false
    #     ssl_verify: true
    #
    # @example Model usage
    #   class Event < ApplicationRecord
    #     self.table_name = 'events'
    #   end
    #
    #   Event.where(user_id: 123).count
    #   Event.insert_all(records)
    #   Event.where(status: 'old').delete_all  # Raises on error!
    #
    class ConnectionAdapter < ::ActiveRecord::ConnectionAdapters::AbstractAdapter
      ADAPTER_NAME = "Clickhouse"

      include SchemaStatements

      # Native database types mapping for ClickHouse
      # Used by migrations and schema definitions
      NATIVE_DATABASE_TYPES = {
        primary_key: "UInt64",
        string: { name: "String" },
        text: { name: "String" },
        integer: { name: "Int32" },
        bigint: { name: "Int64" },
        float: { name: "Float32" },
        decimal: { name: "Decimal", precision: 10, scale: 0 },
        datetime: { name: "DateTime" },
        timestamp: { name: "DateTime64", precision: 3 },
        time: { name: "DateTime" },
        date: { name: "Date" },
        binary: { name: "String" },
        boolean: { name: "UInt8" },
        uuid: { name: "UUID" },
        json: { name: "String" },
      }.freeze

      class << self
        # Creates a new database connection
        # Called by ActiveRecord's connection handler
        #
        # @param connection [Object, nil] existing connection (unused)
        # @param logger [Logger] Rails logger
        # @param connection_options [Hash] unused
        # @param config [Hash] database configuration
        # @return [ConnectionAdapter] the adapter instance
        def new_client(config)
          clickhouse_config = build_clickhouse_config(config)
          clickhouse_config.validate!
          ClickhouseRuby::Client.new(clickhouse_config)
        end

        private

        # Build a ClickhouseRuby::Configuration from Rails database.yml config
        #
        # @param config [Hash] database configuration hash
        # @return [ClickhouseRuby::Configuration] configured client
        def build_clickhouse_config(config)
          ClickhouseRuby::Configuration.new.tap do |c|
            c.host = config[:host] || "localhost"
            c.port = config[:port]&.to_i || 8123
            c.database = config[:database] || "default"
            c.username = config[:username]
            c.password = config[:password]
            c.ssl = config[:ssl]
            # SECURITY: SSL verification enabled by default
            # Only disable in development with explicit ssl_verify: false
            c.ssl_verify = config.fetch(:ssl_verify, true)
            c.ssl_ca_path = config[:ssl_ca_path]
            c.connect_timeout = config[:connect_timeout]&.to_i || 10
            c.read_timeout = config[:read_timeout]&.to_i || 60
            c.write_timeout = config[:write_timeout]&.to_i || 60
            c.pool_size = config[:pool]&.to_i || 5
          end
        end
      end

      # Initialize a new ConnectionAdapter
      #
      # @param connection [Object, nil] existing connection
      # @param logger [Logger] Rails logger
      # @param connection_options [Array] connection options
      # @param config [Hash] database configuration
      def initialize(connection, logger = nil, _connection_options = nil, config = {})
        @config = config.symbolize_keys
        @clickhouse_client = nil
        @connection_parameters = nil

        super(connection, logger, config)

        # Extend ActiveRecord::Relation with our methods
        ::ActiveRecord::Relation.include(RelationExtensions)
      end

      # Returns the adapter name
      #
      # @return [String] 'Clickhouse'
      def adapter_name
        ADAPTER_NAME
      end

      # Returns native database types
      #
      # @return [Hash] type mapping
      def native_database_types
        NATIVE_DATABASE_TYPES
      end

      # ========================================
      # Connection Management
      # ========================================

      # Check if the connection is active
      #
      # @return [Boolean] true if connected and responding
      def active?
        return false unless @clickhouse_client

        # Ping ClickHouse to verify connection
        execute_internal("SELECT 1")
        true
      rescue ClickhouseRuby::Error
        false
      end

      # Check if connected to the database
      #
      # @return [Boolean] true if we have a client instance
      def connected?
        !@clickhouse_client.nil?
      end

      # Disconnect from the database
      #
      # @return [void]
      def disconnect!
        super
        @clickhouse_client&.close if @clickhouse_client.respond_to?(:close)
        @clickhouse_client = nil
      end

      # Reconnect to the database
      #
      # @return [void]
      def reconnect!
        super
        disconnect!
        connect
      end

      # Clear the connection (called when returning connection to pool)
      #
      # @return [void]
      def reset!
        reconnect!
      end

      # Establish connection to ClickHouse
      #
      # @return [void]
      def connect
        @clickhouse_client = self.class.new_client(@config)
      end

      # ========================================
      # ClickHouse Capabilities
      # These return false because ClickHouse doesn't support these features
      # ========================================

      # ClickHouse doesn't support DDL transactions
      #
      # @return [Boolean] false
      def supports_ddl_transactions?
        false
      end

      # ClickHouse doesn't support savepoints
      #
      # @return [Boolean] false
      def supports_savepoints?
        false
      end

      # ClickHouse doesn't support transaction isolation levels
      #
      # @return [Boolean] false
      def supports_transaction_isolation?
        false
      end

      # ClickHouse doesn't support INSERT RETURNING
      #
      # @return [Boolean] false
      def supports_insert_returning?
        false
      end

      # ClickHouse doesn't support foreign keys
      #
      # @return [Boolean] false
      def supports_foreign_keys?
        false
      end

      # ClickHouse doesn't support check constraints in the traditional sense
      #
      # @return [Boolean] false
      def supports_check_constraints?
        false
      end

      # ClickHouse doesn't support partial indexes
      #
      # @return [Boolean] false
      def supports_partial_index?
        false
      end

      # ClickHouse doesn't support expression indexes
      #
      # @return [Boolean] false
      def supports_expression_index?
        false
      end

      # ClickHouse doesn't support standard views (has MATERIALIZED VIEWS)
      #
      # @return [Boolean] false
      def supports_views?
        false
      end

      # ClickHouse supports datetime with precision (DateTime64)
      #
      # @return [Boolean] true
      def supports_datetime_with_precision?
        true
      end

      # ClickHouse supports JSON type (as String with JSON functions)
      #
      # @return [Boolean] true
      def supports_json?
        true
      end

      # ClickHouse doesn't support standard comments on columns
      #
      # @return [Boolean] false
      def supports_comments?
        false
      end

      # ClickHouse doesn't support bulk alter
      #
      # @return [Boolean] false
      def supports_bulk_alter?
        false
      end

      # ClickHouse supports EXPLAIN
      #
      # @return [Boolean] true
      def supports_explain?
        true
      end

      # ========================================
      # Query Execution
      # CRITICAL: Never silently fail - always propagate errors
      # See: clickhouse-activerecord Issue #230
      # ========================================

      # Execute a SQL query
      # CRITICAL: This method MUST raise on errors, never silently fail
      #
      # @param sql [String] the SQL query
      # @param name [String] query name for logging
      # @return [ClickhouseRuby::Result] query result
      # @raise [ClickhouseRuby::QueryError] on ClickHouse errors
      def execute(sql, name = nil)
        ensure_connected!

        log(sql, name) do
          result = execute_internal(sql)
          # CRITICAL: Check for errors and raise them
          # ClickHouse may return 200 OK with error in body
          raise_if_error!(result)
          result
        end
      rescue ClickhouseRuby::Error => e
        # Re-raise ClickhouseRuby errors with the SQL context
        raise_query_error(e, sql)
      rescue StandardError => e
        # Wrap unexpected errors
        raise ClickhouseRuby::QueryError.new(
          "Query execution failed: #{e.message}",
          sql: sql,
          original_error: e,
        )
      end

      # Execute an INSERT statement
      # For bulk inserts, use insert_all which is more efficient
      #
      # @param sql [String] the INSERT SQL
      # @param name [String] query name for logging
      # @param pk [String, nil] primary key column
      # @param id_value [Object, nil] id value
      # @param sequence_name [String, nil] sequence name (unused)
      # @param binds [Array] bind values
      # @return [Object] the id value
      # @raise [ClickhouseRuby::QueryError] on ClickHouse errors
      def exec_insert(sql, name = nil, _binds = [], _pk = nil, _sequence_name = nil)
        execute(sql, name)
        # ClickHouse doesn't return inserted IDs
        # Return nil as we can't get the last insert ID
        nil
      end

      # Execute a DELETE statement
      # CRITICAL: This method MUST raise on errors (Issue #230)
      #
      # ClickHouse DELETE syntax: ALTER TABLE table DELETE WHERE condition
      # This method handles the conversion automatically via Arel visitor
      #
      # @param sql [String] the DELETE SQL (converted to ALTER TABLE ... DELETE)
      # @param name [String] query name for logging
      # @param binds [Array] bind values
      # @return [Integer] number of affected rows (estimated, ClickHouse doesn't return exact count)
      # @raise [ClickhouseRuby::QueryError] on ClickHouse errors - NEVER silently fails
      def exec_delete(sql, name = nil, _binds = [])
        ensure_connected!

        # The Arel visitor should have already converted this to
        # ALTER TABLE ... DELETE WHERE syntax
        # But if it's standard DELETE, convert it here
        clickhouse_sql = convert_delete_to_alter(sql)

        log(clickhouse_sql, name || "DELETE") do
          result = execute_internal(clickhouse_sql)
          # CRITICAL: Raise on any error
          raise_if_error!(result)

          # ClickHouse doesn't return affected row count for mutations
          # Return 0 as a safe default, but the operation succeeded
          0
        end
      rescue ClickhouseRuby::Error => e
        # CRITICAL: Always propagate errors, never silently fail
        raise_query_error(e, sql)
      rescue StandardError => e
        raise ClickhouseRuby::QueryError.new(
          "DELETE failed: #{e.message}",
          sql: sql,
          original_error: e,
        )
      end

      # Execute an UPDATE statement
      # CRITICAL: This method MUST raise on errors
      #
      # ClickHouse UPDATE syntax: ALTER TABLE table UPDATE col = val WHERE condition
      # This method handles the conversion automatically via Arel visitor
      #
      # @param sql [String] the UPDATE SQL (converted to ALTER TABLE ... UPDATE)
      # @param name [String] query name for logging
      # @param binds [Array] bind values
      # @return [Integer] number of affected rows (estimated)
      # @raise [ClickhouseRuby::QueryError] on ClickHouse errors
      def exec_update(sql, name = nil, _binds = [])
        ensure_connected!

        # The Arel visitor should have already converted this to
        # ALTER TABLE ... UPDATE ... WHERE syntax
        clickhouse_sql = convert_update_to_alter(sql)

        log(clickhouse_sql, name || "UPDATE") do
          result = execute_internal(clickhouse_sql)
          raise_if_error!(result)

          # ClickHouse doesn't return affected row count for mutations
          0
        end
      rescue ClickhouseRuby::Error => e
        raise_query_error(e, sql)
      rescue StandardError => e
        raise ClickhouseRuby::QueryError.new(
          "UPDATE failed: #{e.message}",
          sql: sql,
          original_error: e,
        )
      end

      # Execute a raw query, returning results
      #
      # @param sql [String] the SQL query
      # @param name [String] query name for logging
      # @param binds [Array] bind values
      # @param prepare [Boolean] whether to prepare (ignored, ClickHouse doesn't support)
      # @return [ClickhouseRuby::Result] query result
      def exec_query(sql, name = "SQL", _binds = [], prepare: false)
        execute(sql, name)
      end

      # ========================================
      # Transaction Methods (ClickHouse has limited support)
      # ========================================

      # Begin a transaction (no-op for ClickHouse)
      # ClickHouse doesn't support multi-statement transactions
      #
      # @return [void]
      def begin_db_transaction
        # No-op: ClickHouse doesn't support transactions
      end

      # Commit a transaction (no-op for ClickHouse)
      # All statements are auto-committed in ClickHouse
      #
      # @return [void]
      def commit_db_transaction
        # No-op: ClickHouse doesn't support transactions
      end

      # Rollback a transaction (no-op for ClickHouse)
      # ClickHouse doesn't support rollback
      #
      # @return [void]
      def exec_rollback_db_transaction
        # No-op: ClickHouse doesn't support transactions
        # Log a warning since rollback was requested but cannot be performed
        @logger&.warn("ClickHouse does not support transaction rollback")
      end

      # ========================================
      # Quoting
      # ========================================

      # Quote a column name for ClickHouse
      # ClickHouse uses backticks or double quotes for identifiers
      #
      # @param name [String, Symbol] the column name
      # @return [String] the quoted column name
      def quote_column_name(name)
        "`#{name.to_s.gsub("`", "``")}`"
      end

      # Quote a table name for ClickHouse
      #
      # @param name [String, Symbol] the table name
      # @return [String] the quoted table name
      def quote_table_name(name)
        "`#{name.to_s.gsub("`", "``")}`"
      end

      # Quote a string value for ClickHouse
      #
      # @param string [String] the string to quote
      # @return [String] the quoted string
      def quote_string(string)
        string.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'")
      end

      # ========================================
      # Arel Visitor
      # ========================================

      # Returns the Arel visitor for ClickHouse SQL generation
      #
      # @return [ArelVisitor] the visitor instance
      def arel_visitor
        @arel_visitor ||= ArelVisitor.new(self)
      end

      # ========================================
      # Type Mapping
      # ========================================

      # Initialize the type map with ClickHouse types
      #
      # @param m [ActiveRecord::Type::TypeMap] the type map to populate
      # @return [void]
      def initialize_type_map(m = type_map)
        # Register standard types
        register_class_with_limit m, /^String/i, ::ActiveRecord::Type::String
        register_class_with_limit m, /^FixedString/i, ::ActiveRecord::Type::String

        # Integer types
        m.register_type(/^Int8/i, ::ActiveRecord::Type::Integer.new(limit: 1))
        m.register_type(/^Int16/i, ::ActiveRecord::Type::Integer.new(limit: 2))
        m.register_type(/^Int32/i, ::ActiveRecord::Type::Integer.new(limit: 4))
        m.register_type(/^Int64/i, ::ActiveRecord::Type::Integer.new(limit: 8))
        m.register_type(/^UInt8/i, ::ActiveRecord::Type::Integer.new(limit: 1))
        m.register_type(/^UInt16/i, ::ActiveRecord::Type::Integer.new(limit: 2))
        m.register_type(/^UInt32/i, ::ActiveRecord::Type::Integer.new(limit: 4))
        m.register_type(/^UInt64/i, ::ActiveRecord::Type::Integer.new(limit: 8))

        # Float types
        m.register_type(/^Float32/i, ::ActiveRecord::Type::Float.new)
        m.register_type(/^Float64/i, ::ActiveRecord::Type::Float.new)

        # Decimal types
        m.register_type(/^Decimal/i, ::ActiveRecord::Type::Decimal.new)

        # Date/Time types
        m.register_type(/^Date$/i, ::ActiveRecord::Type::Date.new)
        m.register_type(/^DateTime/i, ::ActiveRecord::Type::DateTime.new)
        m.register_type(/^DateTime64/i, ::ActiveRecord::Type::DateTime.new)

        # Boolean (UInt8 with 0/1)
        m.register_type(/^Bool/i, ::ActiveRecord::Type::Boolean.new)

        # UUID
        m.register_type(/^UUID/i, ::ActiveRecord::Type::String.new)

        # Nullable wrapper - extract inner type
        m.register_type(/^Nullable\((.+)\)/i) do |sql_type|
          inner_type = sql_type.match(/^Nullable\((.+)\)/i)[1]
          lookup_cast_type(inner_type)
        end

        # Array types
        m.register_type(/^Array\(/i, ::ActiveRecord::Type::String.new)

        # Map types
        m.register_type(/^Map\(/i, ::ActiveRecord::Type::String.new)

        # Tuple types
        m.register_type(/^Tuple\(/i, ::ActiveRecord::Type::String.new)

        # Enum types (treated as strings)
        m.register_type(/^Enum/i, ::ActiveRecord::Type::String.new)

        # LowCardinality wrapper
        m.register_type(/^LowCardinality\((.+)\)/i) do |sql_type|
          inner_type = sql_type.match(/^LowCardinality\((.+)\)/i)[1]
          lookup_cast_type(inner_type)
        end
      end

      private

      # Ensure we have an active connection
      #
      # @raise [ClickhouseRuby::ConnectionNotEstablished] if not connected
      def ensure_connected!
        connect unless connected?

        return if @clickhouse_client

        raise ClickhouseRuby::ConnectionNotEstablished,
              "No connection to ClickHouse. Call connect first."
      end

      # Execute SQL through the ClickhouseRuby client
      #
      # @param sql [String] the SQL to execute
      # @return [ClickhouseRuby::Result] the result
      def execute_internal(sql)
        @clickhouse_client.execute(sql)
      end

      # Check if result contains an error and raise it
      #
      # @param result [ClickhouseRuby::Result] the result to check
      # @raise [ClickhouseRuby::QueryError] if result contains an error
      def raise_if_error!(result)
        # ClickhouseRuby::Result should raise errors, but double-check
        return unless result.respond_to?(:error?) && result.error?

        raise ClickhouseRuby::QueryError.new(
          result.error_message,
          code: result.error_code,
          http_status: result.http_status,
        )
      end

      # Raise a query error with SQL context
      #
      # @param error [ClickhouseRuby::Error] the original error
      # @param sql [String] the SQL that caused the error
      # @raise [ClickhouseRuby::QueryError] always
      def raise_query_error(error, sql)
        if error.is_a?(ClickhouseRuby::QueryError)
          # Re-raise with SQL if not already set
          raise error unless error.sql.nil?

          raise ClickhouseRuby::QueryError.new(
            error.message,
            code: error.code,
            http_status: error.http_status,
            sql: sql,
            original_error: error.original_error,
          )

        else
          raise ClickhouseRuby::QueryError.new(
            error.message,
            sql: sql,
            original_error: error,
          )
        end
      end

      # Convert standard DELETE to ClickHouse ALTER TABLE DELETE
      #
      # Standard: DELETE FROM table WHERE condition
      # ClickHouse: ALTER TABLE table DELETE WHERE condition
      #
      # @param sql [String] the DELETE SQL
      # @return [String] the converted SQL
      def convert_delete_to_alter(sql)
        # Check if already in ALTER TABLE format
        return sql if sql.strip.match?(/^ALTER\s+TABLE/i)

        # Parse standard DELETE
        if (match = sql.strip.match(/^DELETE\s+FROM\s+(\S+)(?:\s+WHERE\s+(.+))?$/im))
          table = match[1]
          where_clause = match[2]

          if where_clause
            "ALTER TABLE #{table} DELETE WHERE #{where_clause}"
          else
            # DELETE without WHERE - delete all rows
            "ALTER TABLE #{table} DELETE WHERE 1=1"
          end
        else
          # Return as-is if we can't parse it
          sql
        end
      end

      # Convert standard UPDATE to ClickHouse ALTER TABLE UPDATE
      #
      # Standard: UPDATE table SET col = val WHERE condition
      # ClickHouse: ALTER TABLE table UPDATE col = val WHERE condition
      #
      # @param sql [String] the UPDATE SQL
      # @return [String] the converted SQL
      def convert_update_to_alter(sql)
        # Check if already in ALTER TABLE format
        return sql if sql.strip.match?(/^ALTER\s+TABLE/i)

        # Parse standard UPDATE
        if (match = sql.strip.match(/^UPDATE\s+(\S+)\s+SET\s+(.+?)\s+WHERE\s+(.+)$/im))
          table = match[1]
          set_clause = match[2]
          where_clause = match[3]

          "ALTER TABLE #{table} UPDATE #{set_clause} WHERE #{where_clause}"
        elsif (match = sql.strip.match(/^UPDATE\s+(\S+)\s+SET\s+(.+)$/im))
          # UPDATE without WHERE
          table = match[1]
          set_clause = match[2]

          "ALTER TABLE #{table} UPDATE #{set_clause} WHERE 1=1"
        else
          # Return as-is if we can't parse it
          sql
        end
      end

      # Register a type class with limit support
      #
      # @param mapping [TypeMap] the type map
      # @param pattern [Regexp] the pattern to match
      # @param klass [Class] the type class
      def register_class_with_limit(mapping, pattern, klass)
        mapping.register_type(pattern) do |sql_type|
          limit = extract_limit(sql_type)
          klass.new(limit: limit)
        end
      end

      # Extract limit from a type string (e.g., FixedString(100))
      #
      # @param sql_type [String] the SQL type
      # @return [Integer, nil] the limit or nil
      def extract_limit(sql_type)
        return unless (match = sql_type.match(/\((\d+)\)/))

        match[1].to_i
      end
    end
  end
end

# Register the adapter with ActiveRecord
if defined?(ActiveRecord::ConnectionAdapters)
  if ActiveRecord::ConnectionAdapters.respond_to?(:register)
    ActiveRecord::ConnectionAdapters.register(
      "clickhouse",
      "ClickhouseRuby::ActiveRecord::ConnectionAdapter",
      "clickhouse_ruby/active_record/connection_adapter",
    )
  end
end
