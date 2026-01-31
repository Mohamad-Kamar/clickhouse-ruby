# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'openssl'

module ClickhouseRuby
  # Single HTTP connection wrapper for ClickHouse communication
  #
  # Provides a thin wrapper around Net::HTTP with:
  # - SSL/TLS with verification ON by default (security best practice)
  # - Configurable timeouts
  # - Keep-alive support
  # - Health check via ping
  #
  # @example Creating a connection
  #   connection = ClickhouseRuby::Connection.new(
  #     host: 'localhost',
  #     port: 8123,
  #     use_ssl: false
  #   )
  #   connection.ping  # => true
  #
  # @example With SSL (verification enabled by default)
  #   connection = ClickhouseRuby::Connection.new(
  #     host: 'clickhouse.example.com',
  #     port: 8443,
  #     use_ssl: true,
  #     ssl_verify: true,  # This is the default!
  #     ssl_ca_path: '/path/to/ca-bundle.crt'
  #   )
  #
  class Connection
    # @return [String] the ClickHouse host
    attr_reader :host

    # @return [Integer] the ClickHouse port
    attr_reader :port

    # @return [String] the database name
    attr_reader :database

    # @return [String, nil] username for authentication
    attr_reader :username

    # @return [Boolean] whether SSL is enabled
    attr_reader :use_ssl

    # @return [Boolean] whether the connection is currently open
    attr_reader :connected
    alias connected? connected

    # @return [Time, nil] when the connection was last used
    attr_reader :last_used_at

    # Creates a new connection
    #
    # @param host [String] ClickHouse server hostname
    # @param port [Integer] ClickHouse HTTP port
    # @param database [String] database name
    # @param username [String, nil] username for authentication
    # @param password [String, nil] password for authentication
    # @param use_ssl [Boolean] whether to use SSL/TLS
    # @param ssl_verify [Boolean] whether to verify SSL certificates (default: true)
    # @param ssl_ca_path [String, nil] path to CA certificate file
    # @param connect_timeout [Integer] connection timeout in seconds
    # @param read_timeout [Integer] read timeout in seconds
    # @param write_timeout [Integer] write timeout in seconds
    def initialize(
      host:,
      port: 8123,
      database: 'default',
      username: nil,
      password: nil,
      use_ssl: false,
      ssl_verify: true,
      ssl_ca_path: nil,
      connect_timeout: 10,
      read_timeout: 60,
      write_timeout: 60
    )
      @host = host
      @port = port
      @database = database
      @username = username
      @password = password
      @use_ssl = use_ssl
      @ssl_verify = ssl_verify
      @ssl_ca_path = ssl_ca_path
      @connect_timeout = connect_timeout
      @read_timeout = read_timeout
      @write_timeout = write_timeout

      @http = nil
      @connected = false
      @last_used_at = nil
      @mutex = Mutex.new
    end

    # Establishes the HTTP connection
    #
    # @return [self]
    # @raise [ConnectionNotEstablished] if connection fails
    # @raise [SSLError] if SSL handshake fails
    def connect
      @mutex.synchronize do
        return self if @connected && @http&.started?

        begin
          @http = build_http
          @http.start
          @connected = true
          @last_used_at = Time.now
        rescue OpenSSL::SSL::SSLError => e
          @connected = false
          raise SSLError.new(
            "SSL connection failed: #{e.message}",
            original_error: e
          )
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          @connected = false
          raise ConnectionNotEstablished.new(
            "Failed to connect to #{@host}:#{@port}: #{e.message}",
            original_error: e
          )
        rescue Net::OpenTimeout => e
          @connected = false
          raise ConnectionTimeout.new(
            "Connection timeout to #{@host}:#{@port}",
            original_error: e
          )
        end
      end

      self
    end

    # Closes the HTTP connection
    #
    # @return [self]
    def disconnect
      @mutex.synchronize do
        if @http&.started?
          @http.finish rescue nil
        end
        @http = nil
        @connected = false
      end

      self
    end

    # Reconnects by closing and reopening the connection
    #
    # @return [self]
    def reconnect
      disconnect
      connect
    end

    # Executes an HTTP POST request
    #
    # @param path [String] the request path
    # @param body [String] the request body (SQL query)
    # @param headers [Hash] additional headers
    # @return [Net::HTTPResponse] the response
    # @raise [ConnectionNotEstablished] if not connected
    # @raise [ConnectionTimeout] if request times out
    def post(path, body, headers = {})
      ensure_connected

      request = Net::HTTP::Post.new(path)
      request.body = body

      # Set default headers
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request['Accept'] = 'application/json'
      request['User-Agent'] = "ClickhouseRuby/#{ClickhouseRuby::VERSION} Ruby/#{RUBY_VERSION}"

      # Add authentication
      if @username
        request.basic_auth(@username, @password || '')
      end

      # Merge custom headers
      headers.each { |k, v| request[k] = v }

      execute_request(request)
    end

    # Executes an HTTP GET request
    #
    # @param path [String] the request path
    # @param headers [Hash] additional headers
    # @return [Net::HTTPResponse] the response
    def get(path, headers = {})
      ensure_connected

      request = Net::HTTP::Get.new(path)
      request['Accept'] = 'application/json'
      request['User-Agent'] = "ClickhouseRuby/#{ClickhouseRuby::VERSION} Ruby/#{RUBY_VERSION}"

      if @username
        request.basic_auth(@username, @password || '')
      end

      headers.each { |k, v| request[k] = v }

      execute_request(request)
    end

    # Checks if ClickHouse is reachable and responsive
    #
    # @return [Boolean] true if ClickHouse responds to ping
    def ping
      connect unless connected?

      response = get('/ping')
      response.code == '200' && response.body&.strip == 'Ok.'
    rescue StandardError
      false
    end

    # Returns whether the connection is healthy
    #
    # @return [Boolean] true if connected and HTTP connection is active
    def healthy?
      @connected && @http&.started?
    end

    # Returns whether the connection has been idle too long
    #
    # @param max_idle_seconds [Integer] maximum idle time in seconds
    # @return [Boolean] true if connection is stale
    def stale?(max_idle_seconds = 300)
      return true unless @last_used_at

      Time.now - @last_used_at > max_idle_seconds
    end

    # Returns a string representation of the connection
    #
    # @return [String]
    def inspect
      scheme = @use_ssl ? 'https' : 'http'
      status = @connected ? 'connected' : 'disconnected'
      "#<#{self.class.name} #{scheme}://#{@host}:#{@port} #{status}>"
    end

    private

    # Builds the Net::HTTP instance with proper configuration
    #
    # @return [Net::HTTP]
    def build_http
      http = Net::HTTP.new(@host, @port)

      # Timeouts
      http.open_timeout = @connect_timeout
      http.read_timeout = @read_timeout
      http.write_timeout = @write_timeout

      # SSL configuration
      if @use_ssl
        http.use_ssl = true

        # SECURITY: Enable SSL verification by default
        # This is critical - existing gems disable this which is a vulnerability
        if @ssl_verify
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.ca_file = @ssl_ca_path if @ssl_ca_path
        else
          # Only disable if explicitly requested (development only!)
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          warn '[ClickhouseRuby] WARNING: SSL verification disabled. Insecure for production.'
        end

        # Use modern TLS versions
        http.min_version = OpenSSL::SSL::TLS1_2_VERSION
      end

      # Enable keep-alive
      http.keep_alive_timeout = 30

      http
    end

    # Ensures the connection is established
    #
    # @raise [ConnectionNotEstablished] if not connected
    def ensure_connected
      unless @connected && @http&.started?
        connect
      end
    end

    # Executes an HTTP request with error handling
    #
    # @param request [Net::HTTPRequest] the request to execute
    # @return [Net::HTTPResponse]
    def execute_request(request)
      @mutex.synchronize do
        begin
          response = @http.request(request)
          @last_used_at = Time.now
          response
        rescue Net::ReadTimeout => e
          @connected = false
          raise ConnectionTimeout.new(
            "Read timeout: #{e.message}",
            original_error: e
          )
        rescue Net::WriteTimeout => e
          @connected = false
          raise ConnectionTimeout.new(
            "Write timeout: #{e.message}",
            original_error: e
          )
        rescue Errno::ECONNRESET, Errno::EPIPE, IOError => e
          @connected = false
          raise ConnectionError.new(
            "Connection lost: #{e.message}",
            original_error: e
          )
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          @connected = false
          raise ConnectionNotEstablished.new(
            "Connection failed: #{e.message}",
            original_error: e
          )
        end
      end
    end
  end
end
