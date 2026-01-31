# frozen_string_literal: true

require 'thread'
require 'timeout'

module ClickhouseRuby
  # Thread-safe connection pool for managing multiple ClickHouse connections
  #
  # Features:
  # - Thread-safe checkout/checkin with mutex
  # - Configurable pool size and timeout
  # - Automatic health checks before returning connections
  # - with_connection block pattern for safe usage
  # - Idle connection cleanup
  #
  # @example Basic usage with block (recommended)
  #   pool = ClickhouseRuby::ConnectionPool.new(config)
  #   pool.with_connection do |conn|
  #     response = conn.post('/query', 'SELECT 1')
  #   end
  #
  # @example Manual checkout/checkin (use with caution)
  #   conn = pool.checkout
  #   begin
  #     response = conn.post('/query', 'SELECT 1')
  #   ensure
  #     pool.checkin(conn)
  #   end
  #
  class ConnectionPool
    # @return [Integer] maximum number of connections in the pool
    attr_reader :size

    # @return [Integer] timeout in seconds when waiting for a connection
    attr_reader :timeout

    # Creates a new connection pool
    #
    # @param config [Configuration] connection configuration
    # @param size [Integer] maximum pool size (default from config)
    # @param timeout [Integer] wait timeout in seconds (default from config)
    def initialize(config, size: nil, timeout: nil)
      @config = config
      @size = size || config.pool_size
      @timeout = timeout || config.pool_timeout
      @connection_options = config.to_connection_options

      # Pool state
      @available = []           # Connections available for checkout
      @in_use = []             # Connections currently checked out
      @all_connections = []    # All connections ever created

      # Synchronization
      @mutex = Mutex.new
      @condition = ConditionVariable.new

      # Stats
      @total_checkouts = 0
      @total_timeouts = 0
      @created_at = Time.now
    end

    # Executes a block with a checked-out connection
    #
    # This is the recommended way to use the pool. The connection is
    # automatically returned to the pool when the block completes,
    # even if an exception is raised.
    #
    # @yield [Connection] the checked-out connection
    # @return [Object] the block's return value
    # @raise [PoolTimeout] if no connection becomes available
    def with_connection
      conn = checkout
      begin
        yield conn
      ensure
        checkin(conn)
      end
    end

    # Checks out a connection from the pool
    #
    # If no connections are available and the pool is at capacity,
    # waits up to @timeout seconds for one to become available.
    #
    # @return [Connection] a healthy connection
    # @raise [PoolTimeout] if no connection available within timeout
    # @raise [PoolExhausted] if pool is exhausted and timeout is 0
    def checkout
      deadline = Time.now + @timeout

      @mutex.synchronize do
        loop do
          # Try to get an available connection
          if (conn = get_available_connection)
            @in_use << conn
            @total_checkouts += 1
            return conn
          end

          # Try to create a new connection if under capacity
          if @all_connections.size < @size
            conn = create_connection
            @in_use << conn
            @total_checkouts += 1
            return conn
          end

          # Wait for a connection to be returned
          remaining = deadline - Time.now
          if remaining <= 0
            @total_timeouts += 1
            raise PoolTimeout.new(
              "Could not obtain a connection from the pool within #{@timeout} seconds " \
              "(pool size: #{@size}, in use: #{@in_use.size})"
            )
          end

          @condition.wait(@mutex, remaining)
        end
      end
    end

    # Returns a connection to the pool
    #
    # @param connection [Connection] the connection to return
    # @return [void]
    def checkin(connection)
      return unless connection

      @mutex.synchronize do
        @in_use.delete(connection)

        # Only return healthy connections to the available pool
        if connection.healthy? && !connection.stale?
          @available << connection
        else
          # Disconnect unhealthy connections
          safe_disconnect(connection)
          @all_connections.delete(connection)
        end

        @condition.signal
      end
    end

    # Returns the number of currently available connections
    #
    # @return [Integer]
    def available_count
      @mutex.synchronize { @available.size }
    end

    # Returns the number of connections currently in use
    #
    # @return [Integer]
    def in_use_count
      @mutex.synchronize { @in_use.size }
    end

    # Returns the total number of connections (available + in use)
    #
    # @return [Integer]
    def total_count
      @mutex.synchronize { @all_connections.size }
    end

    # Checks if all connections are currently in use
    #
    # @return [Boolean]
    def exhausted?
      @mutex.synchronize do
        @available.empty? && @all_connections.size >= @size
      end
    end

    # Closes all connections and resets the pool
    #
    # This should be called when shutting down the application.
    #
    # @return [void]
    def shutdown
      @mutex.synchronize do
        (@available + @in_use).each do |conn|
          safe_disconnect(conn)
        end

        @available.clear
        @in_use.clear
        @all_connections.clear
      end
    end

    # Removes idle/unhealthy connections from the pool
    #
    # @param max_idle_seconds [Integer] maximum idle time before removal
    # @return [Integer] number of connections removed
    def cleanup(max_idle_seconds = 300)
      removed = 0

      @mutex.synchronize do
        @available.reject! do |conn|
          if conn.stale?(max_idle_seconds) || !conn.healthy?
            safe_disconnect(conn)
            @all_connections.delete(conn)
            removed += 1
            true
          else
            false
          end
        end
      end

      removed
    end

    # Pings all available connections to check health
    #
    # @return [Hash] status report
    def health_check
      @mutex.synchronize do
        healthy = 0
        unhealthy = 0

        @available.each do |conn|
          if conn.ping
            healthy += 1
          else
            unhealthy += 1
          end
        end

        {
          available: @available.size,
          in_use: @in_use.size,
          total: @all_connections.size,
          capacity: @size,
          healthy: healthy,
          unhealthy: unhealthy
        }
      end
    end

    # Returns pool statistics
    #
    # @return [Hash] pool statistics
    def stats
      @mutex.synchronize do
        {
          size: @size,
          available: @available.size,
          in_use: @in_use.size,
          total_connections: @all_connections.size,
          total_checkouts: @total_checkouts,
          total_timeouts: @total_timeouts,
          uptime_seconds: Time.now - @created_at
        }
      end
    end

    # Returns a string representation of the pool
    #
    # @return [String]
    def inspect
      @mutex.synchronize do
        "#<#{self.class.name} size=#{@size} available=#{@available.size} in_use=#{@in_use.size}>"
      end
    end

    private

    # Gets an available connection from the pool
    #
    # @return [Connection, nil] a healthy connection or nil
    def get_available_connection
      while (conn = @available.pop)
        # Verify the connection is still healthy
        if conn.healthy? && !conn.stale?
          return conn
        else
          # Remove unhealthy connections
          safe_disconnect(conn)
          @all_connections.delete(conn)
        end
      end

      nil
    end

    # Safely disconnects a connection, logging any errors
    #
    # @param connection [Connection] the connection to disconnect
    # @return [void]
    def safe_disconnect(connection)
      connection.disconnect
    rescue StandardError => e
      @config.logger&.warn("[ClickhouseRuby] Disconnect error: #{e.class} - #{e.message}")
    end

    # Creates a new connection
    #
    # @return [Connection] the new connection
    # @raise [ConnectionNotEstablished] if connection fails
    def create_connection
      conn = Connection.new(**@connection_options)
      conn.connect
      @all_connections << conn
      conn
    end
  end
end
