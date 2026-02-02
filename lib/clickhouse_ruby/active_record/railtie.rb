# frozen_string_literal: true

require "rails/railtie"

module ClickhouseRuby
  module ActiveRecord
    # Rails integration for ClickhouseRuby ClickHouse adapter
    #
    # This Railtie hooks into Rails to:
    # - Register the ClickHouse adapter with ActiveRecord
    # - Configure default settings for Rails environments
    # - Set up logging integration
    #
    # @example database.yml
    #   development:
    #     adapter: clickhouse
    #     host: localhost
    #     port: 8123
    #     database: myapp_development
    #
    #   production:
    #     adapter: clickhouse
    #     host: <%= ENV['CLICKHOUSE_HOST'] %>
    #     port: 8443
    #     database: myapp_production
    #     ssl: true
    #     ssl_verify: true
    #
    class Railtie < ::Rails::Railtie
      # Initialize the adapter when ActiveRecord loads
      initializer "clickhouse_ruby.initialize_active_record" do
        # Register the adapter
        ::ActiveSupport.on_load(:active_record) do
          require_relative "connection_adapter"

          # Log that the adapter is being registered
          if defined?(Rails.logger) && Rails.logger
            Rails.logger.info "[ClickhouseRuby] ClickHouse adapter registered with ActiveRecord"
          end
        end
      end

      # Configure database tasks (db:create, db:drop, etc.)
      initializer "clickhouse_ruby.configure_database_tasks" do
        ::ActiveSupport.on_load(:active_record) do
          # Register ClickHouse-specific database tasks
          if defined?(::ActiveRecord::Tasks::DatabaseTasks)
            ::ActiveRecord::Tasks::DatabaseTasks.register_task(/clickhouse/,
                                                               "ClickhouseRuby::ActiveRecord::DatabaseTasks",)
          end
        end
      end

      # Configure the connection pool for Rails
      config.after_initialize do
        # Set up connection pool based on Rails configuration
        if defined?(ActiveRecord::Base)
          # Ensure connections are properly managed
          begin
            ActiveRecord::Base.connection_pool.disconnect!
          rescue StandardError
            nil
          end
        end
      end

      # Add generators namespace for Rails generators
      generators do
        require_relative "generators/migration_generator" if defined?(::Rails::Generators)
      end

      # Log deprecation warnings for known issues
      initializer "clickhouse_ruby.log_deprecation_warnings" do
        ::ActiveSupport.on_load(:active_record) do
          # Warn about features that don't work with ClickHouse
          if defined?(Rails.logger) && Rails.logger
            Rails.logger.debug "[ClickhouseRuby] Note: ClickHouse does not support transactions, savepoints, or foreign keys"
          end
        end
      end
    end

    # Database tasks for Rails (db:create, db:drop, etc.)
    class DatabaseTasks
      delegate :configuration_hash, :root, to: ::ActiveRecord::Tasks::DatabaseTasks

      def self.using_database_configurations?
        true
      end

      # Create a ClickHouse database
      #
      # @param master_configuration_hash [Hash] database configuration
      def create(master_configuration_hash = configuration_hash)
        config = master_configuration_hash.symbolize_keys
        database = config[:database]

        return if database.nil? || database.empty?

        # Connect without database to create it
        temp_config = config.dup
        temp_config[:database] = "default"

        adapter = ConnectionAdapter.new(nil, nil, nil, temp_config)
        adapter.connect
        adapter.create_database(database, if_not_exists: true)
        adapter.disconnect!

        puts "Created database '#{database}'"
      rescue ClickhouseRuby::Error => e
        raise "Failed to create database '#{database}': #{e.message}"
      end

      # Drop a ClickHouse database
      #
      # @param master_configuration_hash [Hash] database configuration
      def drop(master_configuration_hash = configuration_hash)
        config = master_configuration_hash.symbolize_keys
        database = config[:database]

        return if database.nil? || database.empty?

        # Connect without database to drop it
        temp_config = config.dup
        temp_config[:database] = "default"

        adapter = ConnectionAdapter.new(nil, nil, nil, temp_config)
        adapter.connect
        adapter.drop_database(database, if_exists: true)
        adapter.disconnect!

        puts "Dropped database '#{database}'"
      rescue ClickhouseRuby::Error => e
        raise "Failed to drop database '#{database}': #{e.message}"
      end

      # Purge (drop and recreate) a ClickHouse database
      def purge(master_configuration_hash = configuration_hash)
        drop(master_configuration_hash)
        create(master_configuration_hash)
      end

      # Return structure dump (schema)
      #
      # @param master_configuration_hash [Hash] database configuration
      # @param filename [String] path to dump file
      def structure_dump(master_configuration_hash, filename)
        config = master_configuration_hash.symbolize_keys

        adapter = ConnectionAdapter.new(nil, nil, nil, config)
        adapter.connect

        File.open(filename, "w") do |file|
          # Dump each table's CREATE statement
          adapter.tables.each do |table_name|
            result = adapter.execute("SHOW CREATE TABLE #{adapter.quote_table_name(table_name)}")
            create_statement = result.first["statement"] || result.first["Create Table"]
            file.puts "#{create_statement};\n\n"
          end
        end

        adapter.disconnect!
      end

      # Load structure from dump file
      #
      # @param master_configuration_hash [Hash] database configuration
      # @param filename [String] path to dump file
      def structure_load(master_configuration_hash, filename)
        config = master_configuration_hash.symbolize_keys

        adapter = ConnectionAdapter.new(nil, nil, nil, config)
        adapter.connect

        # Read and execute each statement
        sql = File.read(filename)
        statements = sql.split(/;\s*\n/).reject(&:empty?)

        statements.each do |statement|
          adapter.execute(statement.strip) unless statement.strip.empty?
        end

        adapter.disconnect!
      end

      # Charset (not applicable to ClickHouse)
      def charset(_master_configuration_hash = configuration_hash)
        "UTF-8"
      end

      # Collation (not applicable to ClickHouse)
      def collation(_master_configuration_hash = configuration_hash)
        nil
      end
    end
  end
end
