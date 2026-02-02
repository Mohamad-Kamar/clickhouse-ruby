# frozen_string_literal: true

module ClickhouseRuby
  # Instrumentation module for observability and monitoring
  #
  # Provides ActiveSupport::Notifications integration when available,
  # with graceful fallback for non-Rails applications.
  #
  # @example Subscribe to events (with ActiveSupport)
  #   ActiveSupport::Notifications.subscribe(/clickhouse_ruby/) do |name, start, finish, id, payload|
  #     duration = finish - start
  #     Rails.logger.info "#{name} took #{duration}s"
  #   end
  #
  # @example Subscribe to specific events
  #   ActiveSupport::Notifications.subscribe('clickhouse_ruby.query.complete') do |*args|
  #     event = ActiveSupport::Notifications::Event.new(*args)
  #     puts "Query: #{event.payload[:sql]} took #{event.duration}ms"
  #   end
  #
  module Instrumentation
    # Event names for instrumentation
    EVENTS = {
      query_start: "clickhouse_ruby.query.start",
      query_complete: "clickhouse_ruby.query.complete",
      query_error: "clickhouse_ruby.query.error",
      insert_start: "clickhouse_ruby.insert.start",
      insert_complete: "clickhouse_ruby.insert.complete",
      pool_checkout: "clickhouse_ruby.pool.checkout",
      pool_checkin: "clickhouse_ruby.pool.checkin",
      pool_timeout: "clickhouse_ruby.pool.timeout",
    }.freeze

    class << self
      # Check if ActiveSupport::Notifications is available
      #
      # @return [Boolean] true if ActiveSupport::Notifications is available
      def available?
        defined?(ActiveSupport::Notifications)
      end

      # Instrument a block of code with timing and event notification
      #
      # When ActiveSupport::Notifications is available, publishes an event
      # with the given name and payload. Otherwise, still tracks timing
      # for logging purposes.
      #
      # @param event_name [String] the event name to publish
      # @param payload [Hash] additional payload data
      # @yield the block to instrument
      # @return [Object] the result of the block
      #
      # @example
      #   Instrumentation.instrument('clickhouse_ruby.query.complete', sql: 'SELECT 1') do
      #     execute_query
      #   end
      def instrument(event_name, payload = {})
        if available?
          ActiveSupport::Notifications.instrument(event_name, payload) { yield }
        else
          instrument_without_as(event_name, payload) { yield }
        end
      end

      # Publish an event without a block (for start/error events)
      #
      # @param event_name [String] the event name to publish
      # @param payload [Hash] the event payload
      # @return [void]
      def publish(event_name, payload = {})
        return unless available?

        ActiveSupport::Notifications.publish(event_name, payload)
      end

      # Returns a monotonic timestamp for duration calculation
      #
      # Uses Process.clock_gettime for accurate timing that isn't
      # affected by system clock changes.
      #
      # @return [Float] monotonic timestamp in seconds
      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Calculate duration in milliseconds from a start time
      #
      # @param started_at [Float] monotonic start time
      # @return [Float] duration in milliseconds
      def duration_ms(started_at)
        (monotonic_time - started_at) * 1000
      end

      private

      # Fallback instrumentation when ActiveSupport is not available
      #
      # Still tracks timing so it can be used for logging.
      #
      # @param event_name [String] the event name
      # @param payload [Hash] the payload
      # @yield the block to execute
      # @return [Object] the result of the block
      def instrument_without_as(event_name, payload)
        started_at = monotonic_time
        result = yield
        payload[:duration_ms] = duration_ms(started_at)
        result
      rescue StandardError => e
        payload[:duration_ms] = duration_ms(started_at)
        payload[:exception] = [e.class.name, e.message]
        raise
      end
    end

    # Helper module for including instrumentation in classes
    module Helpers
      private

      # Instrument a query operation
      #
      # @param sql [String] the SQL query
      # @param settings [Hash] query settings
      # @yield the block to execute
      # @return [Object] the result
      def instrument_query(sql, settings: {})
        payload = {
          sql: sql,
          settings: settings,
          connection_id: object_id,
        }

        Instrumentation.instrument(EVENTS[:query_complete], payload) { yield }
      end

      # Instrument an insert operation
      #
      # @param table [String] the table name
      # @param row_count [Integer] number of rows
      # @param settings [Hash] query settings
      # @yield the block to execute
      # @return [Object] the result
      def instrument_insert(table, row_count:, settings: {})
        payload = {
          table: table,
          row_count: row_count,
          settings: settings,
          connection_id: object_id,
        }

        Instrumentation.instrument(EVENTS[:insert_complete], payload) { yield }
      end

      # Instrument a pool checkout operation
      #
      # @yield the block to execute
      # @return [Object] the result
      def instrument_pool_checkout
        payload = { pool_id: object_id }

        Instrumentation.instrument(EVENTS[:pool_checkout], payload) { yield }
      end

      # Publish a pool timeout event
      #
      # @param wait_time [Float] how long we waited before timeout
      # @return [void]
      def publish_pool_timeout(wait_time:)
        Instrumentation.publish(EVENTS[:pool_timeout], {
          pool_id: object_id,
          wait_time_ms: wait_time * 1000,
        },)
      end
    end
  end
end
