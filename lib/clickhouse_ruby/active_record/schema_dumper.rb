# frozen_string_literal: true

require "active_record/schema_dumper"

module ClickhouseRuby
  module ActiveRecord
    # Custom schema dumper for ClickHouse databases
    #
    # Extends ActiveRecord::SchemaDumper to properly dump ClickHouse-specific
    # schema elements like engines, ORDER BY, PARTITION BY, and SETTINGS.
    #
    # @example Usage
    #   # Automatically used when running:
    #   rails db:schema:dump
    #
    # @example Manual usage
    #   File.open("db/schema.rb", "w") do |file|
    #     ClickhouseRuby::ActiveRecord::SchemaDumper.dump(connection, file)
    #   end
    #
    class SchemaDumper < ::ActiveRecord::SchemaDumper
      # Dump the schema to a stream
      #
      # @param connection [ConnectionAdapter] the database connection
      # @param stream [IO] the output stream
      # @param _config [ActiveRecord::DatabaseConfigurations::DatabaseConfig] database config (unused)
      # @return [void]
      def self.dump(connection = ::ActiveRecord::Base.connection, stream = $stdout, _config = nil)
        new(connection, generate_options).dump(stream)
        stream
      end

      # Generate options for the dumper
      #
      # @return [Hash] dumper options
      def self.generate_options
        {
          table_name_prefix: ::ActiveRecord::Base.table_name_prefix,
          table_name_suffix: ::ActiveRecord::Base.table_name_suffix,
        }
      end

      private

      # Dump all tables to the stream
      #
      # @param stream [IO] the output stream
      # @return [void]
      def tables(stream)
        table_names = @connection.tables.sort

        table_names.each do |table_name|
          table(table_name, stream)
        end

        # Dump views after tables
        views(stream) if @connection.respond_to?(:views)
      end

      # Dump views to the stream
      #
      # @param stream [IO] the output stream
      # @return [void]
      def views(stream)
        return unless @connection.respond_to?(:views)

        view_names = @connection.views.sort
        return if view_names.empty?

        stream.puts
        stream.puts "  # Views"

        view_names.each do |view_name|
          view(view_name, stream)
        end
      end

      # Dump a single table to the stream
      #
      # @param table_name [String] the table name
      # @param stream [IO] the output stream
      # @return [void]
      def table(table_name, stream)
        columns = @connection.columns(table_name)
        table_options = TableOptionsExtractor.new(@connection, table_name).extract

        # Begin create_table block
        stream.print "  create_table #{table_name.inspect}"
        stream.print ", #{format_options(table_options)}" unless table_options.empty?
        stream.puts " do |t|"

        # Dump columns
        columns.each do |column|
          ColumnDumper.new(column, stream).dump
        end

        stream.puts "  end"
        stream.puts

        # Dump indexes
        dump_indexes(table_name, stream)
      end

      # Dump a view definition to the stream
      #
      # @param view_name [String] the view name
      # @param stream [IO] the output stream
      # @return [void]
      def view(view_name, stream)
        view_definition = extract_view_definition(view_name)
        return unless view_definition

        stream.puts "  execute <<~SQL"
        stream.puts "    #{view_definition}"
        stream.puts "  SQL"
        stream.puts
      end

      # Extract view definition
      #
      # @param view_name [String] the view name
      # @return [String, nil] the CREATE VIEW statement or nil
      def extract_view_definition(view_name)
        sql = "SHOW CREATE TABLE `#{@connection.quote_string(view_name)}`"
        result = @connection.execute(sql, "SCHEMA")
        return nil if result.empty?

        result.first["statement"] || result.first["Create Table"]
      rescue StandardError
        nil
      end

      # Format options hash as Ruby code
      #
      # @param options [Hash] options hash
      # @return [String] formatted options string
      def format_options(options)
        options.map { |key, value| "#{key}: #{value.inspect}" }.join(", ")
      end

      # Dump indexes for a table
      #
      # @param table_name [String] the table name
      # @param stream [IO] the output stream
      # @return [void]
      def dump_indexes(table_name, stream)
        return unless @connection.respond_to?(:indexes)

        table_indexes = @connection.indexes(table_name)
        return if table_indexes.empty?

        table_indexes.each do |index|
          dump_single_index(table_name, index, stream)
        end

        stream.puts
      end

      # Dump a single index
      #
      # @param table_name [String] the table name
      # @param index [Hash] the index information
      # @param stream [IO] the output stream
      # @return [void]
      def dump_single_index(table_name, index, stream)
        stream.print "  add_index #{table_name.inspect}"
        stream.print ", #{index[:expression].inspect}"
        stream.print ", name: #{index[:name].inspect}"
        stream.print ", type: #{index[:type].inspect}" if index[:type]
        stream.print ", granularity: #{index[:granularity]}" if index[:granularity]
        stream.puts
      end

      # Header comment for the schema file
      #
      # @param stream [IO] the output stream
      # @return [void]
      def header(stream)
        write_header_comments(stream)
        stream.puts
        stream.puts "ActiveRecord::Schema[#{::ActiveRecord::Migration.current_version}].define(" \
                    "version: #{schema_version}) do"
      end

      # Write header comments to stream
      #
      # @param stream [IO] the output stream
      # @return [void]
      def write_header_comments(stream)
        stream.puts "# This file is auto-generated from the current state of the database. Instead"
        stream.puts "# of editing this file, please use the migrations feature of Active Record to"
        stream.puts "# incrementally modify your database, and then regenerate this schema definition."
        stream.puts "#"
        stream.puts "# This file is the source Rails uses to define your schema when running"
        stream.puts "# `bin/rails db:schema:load`."
        stream.puts "#"
        stream.puts "# Note: ClickHouse-specific options (engine, order_by, partition_by) are preserved"
        stream.puts "# and required for proper table recreation."
        stream.puts "#"
        stream.puts "# Database: ClickHouse"
        stream.puts "# Adapter: clickhouse_ruby"
        stream.puts "#"
        stream.puts "# It's strongly recommended that you check this file into version control."
      end

      # Get the current schema version
      #
      # @return [String] the schema version
      def schema_version
        if @connection.respond_to?(:migration_context)
          @connection.migration_context.current_version.to_s
        else
          Time.now.utc.strftime("%Y%m%d%H%M%S")
        end
      end

      # Footer for the schema file
      #
      # @param stream [IO] the output stream
      # @return [void]
      def trailer(stream)
        stream.puts "end"
      end
    end

    # Extracts ClickHouse-specific table options
    class TableOptionsExtractor
      def initialize(connection, table_name)
        @connection = connection
        @table_name = table_name
      end

      # Extract table options from system.tables
      #
      # @return [Hash] table options
      def extract
        row = fetch_table_metadata
        return {} unless row

        build_options(row)
      end

      private

      # Fetch table metadata from system.tables
      #
      # @return [Hash, nil] the table metadata row
      def fetch_table_metadata
        sql = <<~SQL
          SELECT engine, sorting_key, partition_key, primary_key, engine_full
          FROM system.tables
          WHERE database = currentDatabase()
            AND name = '#{@connection.quote_string(@table_name)}'
        SQL

        result = @connection.execute(sql, "SCHEMA")
        result.first
      end

      # Build options hash from metadata row
      #
      # @param row [Hash] the metadata row
      # @return [Hash] the options hash
      def build_options(row)
        options = {}
        options[:engine] = row["engine"] if row["engine"] && row["engine"] != "MergeTree"
        options[:order_by] = row["sorting_key"] if row["sorting_key"].present?
        options[:partition_by] = row["partition_key"] if row["partition_key"].present?
        add_primary_key(options, row)
        add_settings(options, row)
        options
      end

      # Add primary key if different from sorting key
      def add_primary_key(options, row)
        return unless row["primary_key"].present? && row["primary_key"] != row["sorting_key"]

        options[:primary_key] = row["primary_key"]
      end

      # Add settings from engine_full
      def add_settings(options, row)
        return unless row["engine_full"]&.include?("SETTINGS")

        settings = row["engine_full"][/SETTINGS\s+(.+)$/i, 1]
        options[:settings] = settings if settings.present?
      end
    end

    # Dumps a single column definition
    class ColumnDumper
      def initialize(column, stream)
        @column = column
        @stream = stream
      end

      # Dump the column definition
      #
      # @return [void]
      def dump
        type = schema_type
        options = column_options

        @stream.print "    t.#{type} #{@column.name.inspect}"
        @stream.print ", #{format_options(options)}" unless options.empty?
        @stream.puts
      end

      private

      # Get the schema type for the column
      #
      # @return [Symbol] the schema type
      def schema_type
        SchemaTypeMapper.map(@column.sql_type.to_s)
      end

      # Extract column options
      #
      # @return [Hash] column options
      def column_options
        ColumnOptionsExtractor.new(@column).extract
      end

      # Format options hash as Ruby code
      def format_options(options)
        options.map { |key, value| "#{key}: #{value.inspect}" }.join(", ")
      end
    end

    # Maps SQL types to schema types
    module SchemaTypeMapper
      # Type patterns and their schema types
      PATTERNS = [
        [/^UInt64$/i, :bigint],
        [/^UInt(8|16|32)$/i, :integer],
        [/^Int(8|16|32)$/i, :integer],
        [/^Int64$/i, :bigint],
        [/^Float(32|64)$/i, :float],
        [/^Decimal/i, :decimal],
        [/^String$/i, :string],
        [/^FixedString/i, :string],
        [/^Date$/i, :date],
        [/^DateTime64/i, :datetime],
        [/^DateTime$/i, :datetime],
        [/^UUID$/i, :uuid],
      ].freeze

      class << self
        # Map a SQL type to schema type
        #
        # @param sql_type [String] the SQL type
        # @return [Symbol] the schema type
        def map(sql_type)
          # Handle wrapper types
          return handle_nullable(sql_type) if sql_type.match?(/^Nullable\(/i)
          return handle_low_cardinality(sql_type) if sql_type.match?(/^LowCardinality\(/i)

          # Handle standard types
          PATTERNS.each do |pattern, type|
            return type if sql_type.match?(pattern)
          end

          :string
        end

        private

        # Handle Nullable wrapper
        def handle_nullable(sql_type)
          inner = sql_type.match(/^Nullable\((.+)\)/i)[1]
          map(inner)
        end

        # Handle LowCardinality wrapper
        def handle_low_cardinality(sql_type)
          inner = sql_type.match(/^LowCardinality\((.+)\)/i)[1]
          map(inner)
        end
      end
    end

    # Extracts column options from a column
    class ColumnOptionsExtractor
      def initialize(column)
        @column = column
        @sql_type = column.sql_type.to_s
      end

      # Extract all column options
      #
      # @return [Hash] the column options
      def extract
        options = {}
        add_nullable(options)
        add_limit(options)
        add_decimal_options(options)
        add_datetime_precision(options)
        add_default(options)
        add_comment(options)
        options
      end

      private

      def add_nullable(options)
        options[:null] = true if @sql_type.match?(/^Nullable/i)
      end

      def add_limit(options)
        return unless (match = @sql_type.match(/^FixedString\((\d+)\)/i))

        options[:limit] = match[1].to_i
      end

      def add_decimal_options(options)
        return unless (match = @sql_type.match(/^Decimal\((\d+),\s*(\d+)\)/i))

        options[:precision] = match[1].to_i
        options[:scale] = match[2].to_i
      end

      def add_datetime_precision(options)
        return unless (match = @sql_type.match(/^DateTime64\((\d+)\)/i))

        options[:precision] = match[1].to_i
      end

      def add_default(options)
        options[:default] = @column.default if @column.default.present?
      end

      def add_comment(options)
        options[:comment] = @column.comment if @column.comment.present?
      end
    end
  end
end

# Register the custom schema dumper with ActiveRecord
if defined?(ActiveRecord::SchemaDumper)
  # Override the default dumper for ClickHouse connections
  module ClickhouseRuby
    module ActiveRecord
      module SchemaDumperExtension
        def dump(connection = ::ActiveRecord::Base.connection, stream = $stdout, config = nil)
          if connection.adapter_name == "Clickhouse"
            ClickhouseRuby::ActiveRecord::SchemaDumper.dump(connection, stream, config)
          else
            super
          end
        end
      end
    end
  end

  ActiveRecord::SchemaDumper.singleton_class.prepend(ClickhouseRuby::ActiveRecord::SchemaDumperExtension)
end
