# frozen_string_literal: true

require "active_record"
require "active_record/connection_adapters/abstract_adapter"

require_relative "active_record/arel_visitor"
require_relative "active_record/schema_statements"
require_relative "active_record/relation_extensions"
require_relative "active_record/connection_adapter"

# Load Railtie if Rails is available
require_relative "active_record/railtie" if defined?(Rails::Railtie)

module ClickhouseRuby
  # ActiveRecord integration for ClickHouse
  #
  # This module provides full ActiveRecord adapter support for ClickHouse,
  # allowing Rails applications to use ClickHouse as a database backend.
  #
  # @example Configuration in database.yml
  #   development:
  #     adapter: clickhouse
  #     host: localhost
  #     port: 8123
  #     database: analytics_development
  #     username: default
  #     password: ''
  #
  #   production:
  #     adapter: clickhouse
  #     host: <%= ENV['CLICKHOUSE_HOST'] %>
  #     port: 8443
  #     database: analytics_production
  #     ssl: true
  #     ssl_verify: true
  #     username: <%= ENV['CLICKHOUSE_USER'] %>
  #     password: <%= ENV['CLICKHOUSE_PASSWORD'] %>
  #
  # @example Model usage
  #   class Event < ApplicationRecord
  #     self.table_name = 'events'
  #
  #     # ClickHouse doesn't use auto-increment IDs
  #     # Generate UUIDs or use application-level ID generation
  #     before_create :generate_uuid
  #
  #     private
  #
  #     def generate_uuid
  #       self.id ||= SecureRandom.uuid
  #     end
  #   end
  #
  # @example Querying
  #   # Standard ActiveRecord queries work
  #   Event.where(user_id: 123).count
  #   Event.where(created_at: 1.day.ago..).limit(100)
  #   Event.select(:user_id).distinct.pluck(:user_id)
  #
  # @example Bulk inserts (recommended for ClickHouse)
  #   Event.insert_all([
  #     { id: SecureRandom.uuid, name: 'click', user_id: 1 },
  #     { id: SecureRandom.uuid, name: 'view', user_id: 2 }
  #   ])
  #
  # @example Mutations (DELETE/UPDATE)
  #   # IMPORTANT: These raise errors on failure (never silently fail)
  #   Event.where(status: 'old').delete_all
  #   Event.where(user_id: 123).update_all(status: 'archived')
  #
  # @note ClickHouse Limitations
  #   - No transaction support (savepoints, rollback are no-ops)
  #   - No foreign key constraints
  #   - DELETE/UPDATE are asynchronous mutations
  #   - No auto-increment primary keys
  #
  module ActiveRecord
    class << self
      # Check if the adapter is properly registered
      #
      # @return [Boolean] true if the adapter is available
      def registered?
        defined?(::ActiveRecord::ConnectionAdapters) &&
          ::ActiveRecord::ConnectionAdapters.respond_to?(:resolve) &&
          ::ActiveRecord::ConnectionAdapters.resolve("clickhouse").present?
      rescue StandardError
        false
      end

      # Get the adapter version
      #
      # @return [String] the adapter version
      def version
        ClickhouseRuby::VERSION
      end
    end

    # Base class for ClickHouse models
    #
    # All ClickHouse models should inherit from this class or configure
    # the connection manually.
    #
    # @example
    #   class Event < ClickhouseRuby::ActiveRecord::Base
    #     self.table_name = 'events'
    #   end
    #
    #   Event.where(user_id: 123).count
    class Base < ::ActiveRecord::Base
      self.abstract_class = true
    end
  end
end

# Establish a ClickHouse connection method on ActiveRecord::Base
module ActiveRecord
  class Base
    class << self
      # Establish a connection to ClickHouse
      #
      # @param config [Hash] database configuration
      # @return [ConnectionAdapter] the connection adapter
      def clickhouse_connection(config)
        config = config.symbolize_keys

        ClickhouseRuby::ActiveRecord::ConnectionAdapter.new(
          nil,
          logger,
          nil,
          config,
        )
      end
    end
  end
end
