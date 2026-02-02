# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record/migration"

module ClickhouseRuby
  module Generators
    # Rails generator for creating ClickHouse migrations
    #
    # This generator creates migration files with ClickHouse-specific options
    # like ENGINE, ORDER BY, PARTITION BY, and PRIMARY KEY.
    #
    # @example Generate a migration
    #   rails generate clickhouse:migration CreateEvents
    #
    # @example Generate a migration with columns
    #   rails generate clickhouse:migration CreateEvents user_id:integer name:string
    #
    # @example Generate a migration with ClickHouse options
    #   rails generate clickhouse:migration CreateEvents user_id:integer --engine=ReplacingMergeTree --order-by=user_id
    #
    class MigrationGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      argument :attributes, type: :array, default: [], banner: "field:type field:type"

      class_option :engine,
                   type: :string,
                   default: "MergeTree",
                   desc: "ClickHouse table engine (MergeTree, ReplacingMergeTree, SummingMergeTree, etc.)"

      class_option :order_by,
                   type: :string,
                   desc: "ORDER BY clause for MergeTree family engines"

      class_option :partition_by,
                   type: :string,
                   desc: "PARTITION BY clause for data partitioning"

      class_option :primary_key,
                   type: :string,
                   desc: "PRIMARY KEY clause (defaults to ORDER BY if not specified)"

      class_option :settings,
                   type: :string,
                   desc: "Table SETTINGS clause"

      class_option :cluster,
                   type: :string,
                   desc: "Cluster name for distributed tables"

      # Generate the migration file
      #
      # @return [void]
      def create_migration_file
        set_local_assigns!
        validate_engine!

        migration_template "migration.rb.tt", File.join(db_migrate_path, "#{file_name}.rb")
      end

      private

      # Set local variables for use in templates
      #
      # @return [void]
      def set_local_assigns!
        @migration_action = detect_migration_action
      end

      # Detect the type of migration based on the name
      #
      # @return [Symbol] :create_table, :add_column, :remove_column, or :change_table
      def detect_migration_action
        case file_name
        when /^create_/
          :create_table
        when /^add_.*_to_/
          :add_column
        when /^remove_.*_from_/
          :remove_column
        else
          :change_table
        end
      end

      # Validate the engine option
      #
      # @raise [ArgumentError] if the engine is invalid
      # @return [void]
      def validate_engine!
        return if valid_engines.include?(options[:engine])

        raise ArgumentError, "Invalid engine '#{options[:engine]}'. Valid engines: #{valid_engines.join(", ")}"
      end

      # List of valid ClickHouse engines
      #
      # @return [Array<String>] valid engine names
      def valid_engines
        %w[
          MergeTree ReplacingMergeTree SummingMergeTree AggregatingMergeTree
          CollapsingMergeTree VersionedCollapsingMergeTree GraphiteMergeTree
          Log TinyLog StripeLog Memory Null Set Join Buffer Distributed
          MaterializedView Dictionary
        ]
      end

      # Get the table name from the migration name
      #
      # @return [String] the table name
      def table_name
        @table_name ||= extract_table_name
      end

      # Extract table name based on migration action
      #
      # @return [String] the extracted table name
      def extract_table_name
        case @migration_action
        when :create_table then file_name.sub(/^create_/, "")
        when :add_column then file_name.sub(/^add_\w+_to_/, "")
        when :remove_column then file_name.sub(/^remove_\w+_from_/, "")
        else file_name
        end
      end

      # Get the column name for add/remove column migrations
      #
      # @return [String, nil] the column name or nil
      def column_name
        @column_name ||= extract_column_name
      end

      # Extract column name based on migration action
      #
      # @return [String, nil] the extracted column name
      def extract_column_name
        case @migration_action
        when :add_column then file_name[/^add_(\w+)_to_/, 1]
        when :remove_column then file_name[/^remove_(\w+)_from_/, 1]
        end
      end

      # Get the engine with cluster option if specified
      #
      # @return [String] the engine specification
      def engine_with_cluster
        engine = options[:engine]
        return engine unless options[:cluster]

        "Replicated#{engine}('/clickhouse/tables/{shard}/#{table_name}', '{replica}')"
      end

      # Get the ORDER BY clause
      #
      # @return [String, nil] the ORDER BY expression
      def order_by_clause
        options[:order_by] || infer_order_by
      end

      # Infer ORDER BY from primary key or first column
      #
      # @return [String, nil] inferred ORDER BY expression
      def infer_order_by
        return unless @migration_action == :create_table

        # Use id if present, otherwise first attribute
        return "id" if attributes.any? { |attr| attr.name == "id" }
        return attributes.first.name if attributes.any?

        "tuple()"
      end

      # Get the PARTITION BY clause
      #
      # @return [String, nil] the PARTITION BY expression
      def partition_by_clause
        options[:partition_by]
      end

      # Get the PRIMARY KEY clause
      #
      # @return [String, nil] the PRIMARY KEY expression
      def primary_key_clause
        options[:primary_key]
      end

      # Get the SETTINGS clause
      #
      # @return [String, nil] the SETTINGS expression
      def settings_clause
        options[:settings]
      end

      # Convert Rails type to ClickHouse type
      #
      # @param type [String] the Rails type
      # @param attr_options [Hash] type options
      # @return [String] the ClickHouse type
      def clickhouse_type(type, attr_options = {})
        TypeMapper.to_clickhouse(type, attr_options)
      end

      # Get the path to db/migrate directory
      #
      # @return [String] the migration directory path
      def db_migrate_path
        return "db/migrate" unless defined?(Rails.application) && Rails.application

        Rails.application.config.paths["db/migrate"].to_a.first
      end
    end

    # Maps Rails types to ClickHouse types
    module TypeMapper
      # Type mapping from Rails types to ClickHouse types
      TYPE_MAP = {
        primary_key: "UInt64",
        bigint: "Int64",
        time: "DateTime",
        date: "Date",
        binary: "String",
        boolean: "UInt8",
        uuid: "UUID",
        json: "String",
      }.freeze

      # Integer size mapping
      INTEGER_SIZES = {
        1 => "Int8",
        2 => "Int16",
      }.freeze

      class << self
        # Convert a Rails type to ClickHouse type
        #
        # @param type [String, Symbol] the Rails type
        # @param options [Hash] type options
        # @return [String] the ClickHouse type
        def to_clickhouse(type, options = {})
          type_sym = type.to_sym

          # Check simple type map first
          return TYPE_MAP[type_sym] if TYPE_MAP.key?(type_sym)

          # Handle complex types
          complex_type(type_sym, options) || type.to_s
        end

        private

        # Complex type handlers
        COMPLEX_TYPE_HANDLERS = %i[string text integer float decimal datetime timestamp].freeze

        # Handle complex type conversions
        #
        # @param type [Symbol] the Rails type
        # @param options [Hash] type options
        # @return [String, nil] the ClickHouse type or nil
        def complex_type(type, options)
          return string_type(options) if %i[string text].include?(type)

          send("#{type}_type", options) if COMPLEX_TYPE_HANDLERS.include?(type)
        end

        # Get the float type based on limit
        def float_type(options)
          options[:limit] == 8 ? "Float64" : "Float32"
        end

        # Get the timestamp type based on precision
        def timestamp_type(options)
          "DateTime64(#{options[:precision] || 3})"
        end

        # Get the string type based on options
        def string_type(options)
          options[:limit] ? "FixedString(#{options[:limit]})" : "String"
        end

        # Get the integer type based on limit
        def integer_type(options)
          limit = options[:limit]
          return INTEGER_SIZES[limit] if INTEGER_SIZES.key?(limit)
          return "Int32" if limit.nil? || limit <= 4
          return "Int64" if limit <= 8

          "Int32"
        end

        # Get the decimal type based on precision and scale
        def decimal_type(options)
          precision = options[:precision] || 10
          scale = options[:scale] || 0
          "Decimal(#{precision}, #{scale})"
        end

        # Get the datetime type based on precision
        def datetime_type(options)
          options[:precision] ? "DateTime64(#{options[:precision]})" : "DateTime"
        end
      end
    end
  end
end
