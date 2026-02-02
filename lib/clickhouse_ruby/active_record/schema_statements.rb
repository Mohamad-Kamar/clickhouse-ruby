# frozen_string_literal: true

module ClickhouseRuby
  module ActiveRecord
    # Schema introspection and manipulation methods for ClickHouse
    #
    # Provides methods to query and modify database schema through
    # ClickHouse's system tables (system.tables, system.columns, etc.)
    #
    # @note ClickHouse schema operations differ significantly from traditional RDBMS:
    #   - Tables require ENGINE specification (MergeTree, etc.)
    #   - No SERIAL/AUTO_INCREMENT (use generateUUIDv4() or application-side IDs)
    #   - No ALTER TABLE ADD COLUMN migrations (use ALTER TABLE ADD COLUMN)
    #   - Indexes are defined at table creation time
    #
    module SchemaStatements
      # Returns list of tables in the current database
      #
      # @return [Array<String>] list of table names
      def tables
        sql = <<~SQL
          SELECT name
          FROM system.tables
          WHERE database = currentDatabase()
            AND engine NOT IN ('View', 'MaterializedView', 'LiveView')
          ORDER BY name
        SQL

        result = execute(sql, "SCHEMA")
        result.map { |row| row["name"] }
      end

      # Returns list of views in the current database
      #
      # @return [Array<String>] list of view names
      def views
        sql = <<~SQL
          SELECT name
          FROM system.tables
          WHERE database = currentDatabase()
            AND engine IN ('View', 'MaterializedView', 'LiveView')
          ORDER BY name
        SQL

        result = execute(sql, "SCHEMA")
        result.map { |row| row["name"] }
      end

      # Check if a table exists
      #
      # @param table_name [String] the table name to check
      # @return [Boolean] true if the table exists
      def table_exists?(table_name)
        sql = <<~SQL
          SELECT 1
          FROM system.tables
          WHERE database = currentDatabase()
            AND name = '#{quote_string(table_name.to_s)}'
          LIMIT 1
        SQL

        result = execute(sql, "SCHEMA")
        result.any?
      end

      # Check if a view exists
      #
      # @param view_name [String] the view name to check
      # @return [Boolean] true if the view exists
      def view_exists?(view_name)
        sql = <<~SQL
          SELECT 1
          FROM system.tables
          WHERE database = currentDatabase()
            AND name = '#{quote_string(view_name.to_s)}'
            AND engine IN ('View', 'MaterializedView', 'LiveView')
          LIMIT 1
        SQL

        result = execute(sql, "SCHEMA")
        result.any?
      end

      # Returns list of indexes for a table
      #
      # @param table_name [String] the table name
      # @return [Array<Hash>] list of index information
      def indexes(table_name)
        sql = <<~SQL
          SELECT
            name,
            type,
            expr,
            granularity
          FROM system.data_skipping_indices
          WHERE database = currentDatabase()
            AND table = '#{quote_string(table_name.to_s)}'
          ORDER BY name
        SQL

        result = execute(sql, "SCHEMA")
        result.map do |row|
          {
            name: row["name"],
            type: row["type"],
            expression: row["expr"],
            granularity: row["granularity"],
          }
        end
      end

      # Returns list of columns for a table
      #
      # @param table_name [String] the table name
      # @return [Array<Column>] list of column objects
      def columns(table_name)
        sql = <<~SQL
          SELECT
            name,
            type,
            default_kind,
            default_expression,
            comment,
            is_in_primary_key,
            is_in_sorting_key,
            is_in_partition_key
          FROM system.columns
          WHERE database = currentDatabase()
            AND table = '#{quote_string(table_name.to_s)}'
          ORDER BY position
        SQL

        result = execute(sql, "SCHEMA")
        result.map do |row|
          new_column(
            row["name"],
            row["default_expression"],
            fetch_type_metadata(row["type"]),
            row["type"] =~ /^Nullable/i,
            row["comment"],
          )
        end
      end

      # Returns the primary key columns for a table
      #
      # @param table_name [String] the table name
      # @return [Array<String>, nil] primary key column names or nil
      def primary_keys(table_name)
        sql = <<~SQL
          SELECT name
          FROM system.columns
          WHERE database = currentDatabase()
            AND table = '#{quote_string(table_name.to_s)}'
            AND is_in_primary_key = 1
          ORDER BY position
        SQL

        result = execute(sql, "SCHEMA")
        keys = result.map { |row| row["name"] }
        keys.empty? ? nil : keys
      end

      # Create a new table
      #
      # @param table_name [String] the table name
      # @param options [Hash] table options
      # @option options [String] :engine the table engine (default: MergeTree)
      # @option options [String] :order_by ORDER BY clause for MergeTree
      # @option options [String] :partition_by PARTITION BY clause
      # @option options [String] :primary_key PRIMARY KEY clause
      # @option options [String] :settings table SETTINGS
      # @yield [TableDefinition] the table definition block
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def create_table(table_name, **options)
        td = create_table_definition(table_name, **options)

        yield td if block_given?

        sql = schema_creation.accept(td)
        execute(sql, "CREATE TABLE")
      end

      # Drop a table
      #
      # @param table_name [String] the table name
      # @param options [Hash] drop options
      # @option options [Boolean] :if_exists add IF EXISTS clause
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error (unless if_exists: true)
      def drop_table(table_name, **options)
        if_exists = options.fetch(:if_exists, false)
        sql = "DROP TABLE #{if_exists ? "IF EXISTS " : ""}#{quote_table_name(table_name)}"
        execute(sql, "DROP TABLE")
      end

      # Rename a table
      #
      # @param old_name [String] the current table name
      # @param new_name [String] the new table name
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def rename_table(old_name, new_name)
        sql = "RENAME TABLE #{quote_table_name(old_name)} TO #{quote_table_name(new_name)}"
        execute(sql, "RENAME TABLE")
      end

      # Truncate a table (delete all data)
      #
      # @param table_name [String] the table name
      # @param options [Hash] truncate options
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def truncate_table(table_name, **_options)
        sql = "TRUNCATE TABLE #{quote_table_name(table_name)}"
        execute(sql, "TRUNCATE TABLE")
      end

      # Add a column to a table
      #
      # @param table_name [String] the table name
      # @param column_name [String] the column name
      # @param type [Symbol, String] the column type
      # @param options [Hash] column options
      # @option options [String] :after add column after this column
      # @option options [Object] :default default value
      # @option options [Boolean] :null whether column is nullable
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def add_column(table_name, column_name, type, **options)
        sql_type = type_to_sql(type, **options)

        # Handle nullable
        sql_type = "Nullable(#{sql_type})" if options[:null] != false && !sql_type.match?(/^Nullable/i)

        sql = "ALTER TABLE #{quote_table_name(table_name)} ADD COLUMN #{quote_column_name(column_name)} #{sql_type}"

        # Add AFTER clause if specified
        sql += " AFTER #{quote_column_name(options[:after])}" if options[:after]

        # Add DEFAULT if specified
        sql += " DEFAULT #{quote(options[:default])}" if options.key?(:default)

        execute(sql, "ADD COLUMN")
      end

      # Remove a column from a table
      #
      # @param table_name [String] the table name
      # @param column_name [String] the column name
      # @param options [Hash] options (unused)
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def remove_column(table_name, column_name, _type = nil, **_options)
        sql = "ALTER TABLE #{quote_table_name(table_name)} DROP COLUMN #{quote_column_name(column_name)}"
        execute(sql, "DROP COLUMN")
      end

      # Rename a column
      #
      # @param table_name [String] the table name
      # @param old_name [String] the current column name
      # @param new_name [String] the new column name
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def rename_column(table_name, old_name, new_name)
        sql = "ALTER TABLE #{quote_table_name(table_name)} RENAME COLUMN #{quote_column_name(old_name)} TO #{quote_column_name(new_name)}"
        execute(sql, "RENAME COLUMN")
      end

      # Change a column's type
      #
      # @param table_name [String] the table name
      # @param column_name [String] the column name
      # @param type [Symbol, String] the new column type
      # @param options [Hash] column options
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def change_column(table_name, column_name, type, **options)
        sql_type = type_to_sql(type, **options)

        # Handle nullable
        sql_type = "Nullable(#{sql_type})" if options[:null] != false && !sql_type.match?(/^Nullable/i)

        sql = "ALTER TABLE #{quote_table_name(table_name)} MODIFY COLUMN #{quote_column_name(column_name)} #{sql_type}"

        # Add DEFAULT if specified
        sql += " DEFAULT #{quote(options[:default])}" if options.key?(:default)

        execute(sql, "MODIFY COLUMN")
      end

      # Add an index to a table
      # ClickHouse uses data skipping indexes (minmax, set, bloom_filter, etc.)
      #
      # @param table_name [String] the table name
      # @param column_name [String, Array<String>] the column(s) to index
      # @param options [Hash] index options
      # @option options [String] :name the index name
      # @option options [String] :type the index type (minmax, set, bloom_filter, etc.)
      # @option options [Integer] :granularity the index granularity
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def add_index(table_name, column_name, **options)
        columns = Array(column_name).map { |c| quote_column_name(c) }.join(", ")
        index_name = options[:name] || "idx_#{Array(column_name).join("_")}"
        index_type = options[:type] || "minmax"
        granularity = options[:granularity] || 1

        sql = "ALTER TABLE #{quote_table_name(table_name)} ADD INDEX #{quote_column_name(index_name)} (#{columns}) TYPE #{index_type} GRANULARITY #{granularity}"
        execute(sql, "ADD INDEX")
      end

      # Remove an index from a table
      #
      # @param table_name [String] the table name
      # @param options_or_column [Hash, String, Symbol] index name or options with :name
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def remove_index(table_name, options_or_column = nil, **options)
        index_name = if options_or_column.is_a?(Hash)
                       options_or_column[:name]
                     elsif options[:name]
                       options[:name]
                     else
                       "idx_#{Array(options_or_column).join("_")}"
                     end

        sql = "ALTER TABLE #{quote_table_name(table_name)} DROP INDEX #{quote_column_name(index_name)}"
        execute(sql, "DROP INDEX")
      end

      # Check if an index exists
      #
      # @param table_name [String] the table name
      # @param index_name [String] the index name
      # @return [Boolean] true if the index exists
      def index_exists?(table_name, index_name)
        sql = <<~SQL
          SELECT 1
          FROM system.data_skipping_indices
          WHERE database = currentDatabase()
            AND table = '#{quote_string(table_name.to_s)}'
            AND name = '#{quote_string(index_name.to_s)}'
          LIMIT 1
        SQL

        result = execute(sql, "SCHEMA")
        result.any?
      end

      # Check if a column exists
      #
      # @param table_name [String] the table name
      # @param column_name [String] the column name
      # @return [Boolean] true if the column exists
      def column_exists?(table_name, column_name, type = nil, **options)
        sql = <<~SQL
          SELECT type
          FROM system.columns
          WHERE database = currentDatabase()
            AND table = '#{quote_string(table_name.to_s)}'
            AND name = '#{quote_string(column_name.to_s)}'
          LIMIT 1
        SQL

        result = execute(sql, "SCHEMA")
        return false if result.empty?

        if type
          # Check if type matches
          column_type = result.first["type"]
          expected_type = type_to_sql(type, **options)
          column_type.downcase.include?(expected_type.downcase)
        else
          true
        end
      end

      # Get the current database name
      #
      # @return [String] the database name
      def current_database
        result = execute("SELECT currentDatabase() AS db", "SCHEMA")
        result.first["db"]
      end

      # List all databases
      #
      # @return [Array<String>] list of database names
      def databases
        result = execute("SELECT name FROM system.databases ORDER BY name", "SCHEMA")
        result.map { |row| row["name"] }
      end

      # Create a database
      #
      # @param database_name [String] the database name
      # @param options [Hash] database options
      # @option options [Boolean] :if_not_exists add IF NOT EXISTS clause
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def create_database(database_name, **options)
        if_not_exists = options.fetch(:if_not_exists, false)
        sql = "CREATE DATABASE #{if_not_exists ? "IF NOT EXISTS " : ""}`#{database_name}`"
        execute(sql, "CREATE DATABASE")
      end

      # Drop a database
      #
      # @param database_name [String] the database name
      # @param options [Hash] drop options
      # @option options [Boolean] :if_exists add IF EXISTS clause
      # @return [void]
      # @raise [ClickhouseRuby::QueryError] on error
      def drop_database(database_name, **options)
        if_exists = options.fetch(:if_exists, false)
        sql = "DROP DATABASE #{if_exists ? "IF EXISTS " : ""}`#{database_name}`"
        execute(sql, "DROP DATABASE")
      end

      private

      # Convert a Rails type to ClickHouse SQL type
      #
      # @param type [Symbol, String] the Rails type
      # @param options [Hash] type options
      # @return [String] the ClickHouse SQL type
      def type_to_sql(type, **options)
        type = type.to_sym if type.respond_to?(:to_sym)

        case type
        when :primary_key
          "UInt64"
        when :string, :text
          if options[:limit]
            "FixedString(#{options[:limit]})"
          else
            "String"
          end
        when :integer
          case options[:limit]
          when 1 then "Int8"
          when 2 then "Int16"
          when 3, 4 then "Int32"
          when 5, 6, 7, 8 then "Int64"
          else "Int32"
          end
        when :bigint
          "Int64"
        when :float
          options[:limit] == 8 ? "Float64" : "Float32"
        when :decimal
          precision = options[:precision] || 10
          scale = options[:scale] || 0
          "Decimal(#{precision}, #{scale})"
        when :datetime
          if options[:precision]
            "DateTime64(#{options[:precision]})"
          else
            "DateTime"
          end
        when :timestamp
          "DateTime64(#{options[:precision] || 3})"
        when :time
          "DateTime"
        when :date
          "Date"
        when :binary
          "String"
        when :boolean
          "UInt8"
        when :uuid
          "UUID"
        when :json
          "String"
        else
          # Return as-is if it's a ClickHouse type
          type.to_s
        end
      end

      # Create a new column object
      #
      # @param name [String] column name
      # @param default [Object] default value
      # @param sql_type_metadata [Object] type metadata
      # @param null [Boolean] nullable
      # @param comment [String] column comment
      # @return [ActiveRecord::ConnectionAdapters::Column]
      def new_column(name, default, sql_type_metadata, null, comment = nil)
        ::ActiveRecord::ConnectionAdapters::Column.new(
          name,
          default,
          sql_type_metadata,
          null,
          comment: comment,
        )
      end

      # Fetch type metadata for a column type
      #
      # @param sql_type [String] the SQL type string
      # @return [ActiveRecord::ConnectionAdapters::SqlTypeMetadata]
      def fetch_type_metadata(sql_type)
        cast_type = lookup_cast_type(sql_type)
        ::ActiveRecord::ConnectionAdapters::SqlTypeMetadata.new(
          sql_type: sql_type,
          type: cast_type.type,
          limit: cast_type.limit,
          precision: cast_type.precision,
          scale: cast_type.scale,
        )
      end

      # Look up the cast type for a SQL type
      #
      # @param sql_type [String] the SQL type string
      # @return [ActiveRecord::Type::Value] the type object
      def lookup_cast_type(sql_type)
        type_map.lookup(sql_type)
      rescue KeyError
        # Fall back to string if type not found
        ::ActiveRecord::Type::String.new
      end

      # Create a table definition object
      #
      # @param table_name [String] the table name
      # @param options [Hash] table options
      # @return [TableDefinition]
      def create_table_definition(table_name, **options)
        TableDefinition.new(self, table_name, **options)
      end

      # Get the schema creation object
      #
      # @return [SchemaCreation]
      def schema_creation
        SchemaCreation.new(self)
      end
    end

    # Table definition for ClickHouse CREATE TABLE statements
    class TableDefinition
      attr_reader :name, :columns, :options

      def initialize(adapter, name, **options)
        @adapter = adapter
        @name = name
        @columns = []
        @options = options
      end

      # Add a column to the table definition
      #
      # @param name [String, Symbol] the column name
      # @param type [Symbol, String] the column type
      # @param options [Hash] column options
      # @return [self]
      def column(name, type, **options)
        @columns << { name: name.to_s, type: type, options: options }
        self
      end

      # Shorthand methods for common types
      %i[string text integer bigint float decimal datetime timestamp date binary boolean uuid].each do |type|
        define_method(type) do |name, **options|
          column(name, type, **options)
        end
      end

      # Primary key column (UInt64 for ClickHouse)
      def primary_key(name, type = :primary_key, **options)
        column(name, type, **options)
      end

      # Timestamps (created_at, updated_at)
      def timestamps(**options)
        column(:created_at, :datetime, **options)
        column(:updated_at, :datetime, **options)
      end
    end

    # Schema creation for ClickHouse DDL statements
    class SchemaCreation
      def initialize(adapter)
        @adapter = adapter
      end

      # Generate CREATE TABLE SQL from a TableDefinition
      #
      # @param table_definition [TableDefinition] the table definition
      # @return [String] the CREATE TABLE SQL
      def accept(table_definition)
        columns_sql = table_definition.columns.map do |col|
          column_sql(col)
        end.join(",\n  ")

        engine = table_definition.options[:engine] || "MergeTree"
        order_by = table_definition.options[:order_by]
        partition_by = table_definition.options[:partition_by]
        primary_key = table_definition.options[:primary_key]
        settings = table_definition.options[:settings]

        sql = "CREATE TABLE #{@adapter.quote_table_name(table_definition.name)} (\n  #{columns_sql}\n)"
        sql += "\nENGINE = #{engine}"
        sql += "\nORDER BY (#{order_by})" if order_by
        sql += "\nPARTITION BY #{partition_by}" if partition_by
        sql += "\nPRIMARY KEY (#{primary_key})" if primary_key
        sql += "\nSETTINGS #{settings}" if settings

        sql
      end

      private

      def column_sql(col)
        type = type_to_sql(col[:type], **col[:options])

        # Handle nullable
        if col[:options][:null] != false && !type.match?(/^Nullable/i) && !col[:type].to_s.match?(/primary_key/)
          type = "Nullable(#{type})"
        end

        sql = "#{@adapter.quote_column_name(col[:name])} #{type}"

        # Add DEFAULT if specified
        sql += " DEFAULT #{@adapter.quote(col[:options][:default])}" if col[:options].key?(:default)

        sql
      end

      def type_to_sql(type, **options)
        type = type.to_sym if type.respond_to?(:to_sym)

        case type
        when :primary_key
          "UInt64"
        when :string, :text
          options[:limit] ? "FixedString(#{options[:limit]})" : "String"
        when :integer
          case options[:limit]
          when 1 then "Int8"
          when 2 then "Int16"
          when 3, 4 then "Int32"
          when 5, 6, 7, 8 then "Int64"
          else "Int32"
          end
        when :bigint
          "Int64"
        when :float
          options[:limit] == 8 ? "Float64" : "Float32"
        when :decimal
          "Decimal(#{options[:precision] || 10}, #{options[:scale] || 0})"
        when :datetime
          options[:precision] ? "DateTime64(#{options[:precision]})" : "DateTime"
        when :timestamp
          "DateTime64(#{options[:precision] || 3})"
        when :time
          "DateTime"
        when :date
          "Date"
        when :binary
          "String"
        when :boolean
          "UInt8"
        when :uuid
          "UUID"
        when :json
          "String"
        else
          type.to_s
        end
      end
    end
  end
end
