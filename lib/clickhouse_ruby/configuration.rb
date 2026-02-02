# frozen_string_literal: true

module ClickhouseRuby
  # Configuration for ClickhouseRuby client connections
  #
  # @example
  #   config = ClickhouseRuby::Configuration.new
  #   config.host = 'clickhouse.example.com'
  #   config.port = 8443
  #   config.ssl = true
  #
  class Configuration
    # @return [String] the ClickHouse server hostname
    attr_accessor :host

    # @return [Integer] the ClickHouse HTTP port (default: 8123)
    attr_accessor :port

    # @return [String] the database name (default: 'default')
    attr_accessor :database

    # @return [String, nil] the username for authentication
    attr_accessor :username

    # @return [String, nil] the password for authentication
    attr_accessor :password

    # @return [Boolean] whether to use SSL/TLS
    attr_accessor :ssl

    # @return [Boolean] whether to verify SSL certificates (default: true)
    # IMPORTANT: This defaults to true for security. Only disable in development.
    attr_accessor :ssl_verify

    # @return [String, nil] path to custom CA certificate file
    attr_accessor :ssl_ca_path

    # @return [Integer] connection timeout in seconds (default: 10)
    attr_accessor :connect_timeout

    # @return [Integer] read timeout in seconds (default: 60)
    attr_accessor :read_timeout

    # @return [Integer] write timeout in seconds (default: 60)
    attr_accessor :write_timeout

    # @return [Integer] connection pool size (default: 5)
    attr_accessor :pool_size

    # @return [Integer] time to wait for a pool connection in seconds (default: 5)
    attr_accessor :pool_timeout

    # @return [Logger, nil] logger instance for debugging
    attr_accessor :logger

    # @return [Symbol] log level (:debug, :info, :warn, :error)
    attr_accessor :log_level

    # @return [Hash] default ClickHouse settings for all queries
    attr_accessor :default_settings

    # @return [String, nil] compression algorithm ('gzip' or nil to disable)
    attr_accessor :compression

    # @return [Integer] minimum body size in bytes to compress (default: 1024)
    attr_accessor :compression_threshold

    # @return [Integer] maximum number of retry attempts (default: 3)
    attr_accessor :max_retries

    # @return [Float] initial backoff delay in seconds (default: 1.0)
    attr_accessor :initial_backoff

    # @return [Float] maximum backoff delay in seconds (default: 120.0)
    attr_accessor :max_backoff

    # @return [Float] exponential backoff multiplier (default: 1.6)
    attr_accessor :backoff_multiplier

    # @return [Symbol] jitter strategy: :full, :equal, or :none (default: :equal)
    attr_accessor :retry_jitter

    # Creates a new Configuration with sensible defaults
    def initialize
      @host = "localhost"
      @port = 8123
      @database = "default"
      @username = nil
      @password = nil
      @ssl = false
      @ssl_verify = true # SECURITY: Verify certificates by default
      @ssl_ca_path = nil
      @connect_timeout = 10
      @read_timeout = 60
      @write_timeout = 60
      @pool_size = 5
      @pool_timeout = 5
      @logger = nil
      @log_level = :info
      @default_settings = {}
      @compression = nil
      @compression_threshold = 1024
      @max_retries = 3
      @initial_backoff = 1.0
      @max_backoff = 120.0
      @backoff_multiplier = 1.6
      @retry_jitter = :equal
    end

    # Returns the base URL for HTTP connections
    #
    # @return [String] the base URL
    def base_url
      scheme = ssl ? "https" : "http"
      "#{scheme}://#{host}:#{port}"
    end

    # Returns whether SSL should be used based on configuration or port
    # Automatically enables SSL for common secure ports (8443, 443)
    #
    # @return [Boolean] whether to use SSL
    def use_ssl?
      return ssl unless ssl.nil?

      # Auto-enable SSL for secure ports
      [8443, 443].include?(port)
    end

    # Returns whether compression is enabled
    #
    # @return [Boolean] true if compression is set to 'gzip'
    def compression_enabled?
      @compression == "gzip"
    end

    # Returns a hash suitable for creating HTTP connections
    #
    # @return [Hash] connection options
    def to_connection_options
      {
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        use_ssl: use_ssl?,
        ssl_verify: ssl_verify,
        ssl_ca_path: ssl_ca_path,
        connect_timeout: connect_timeout,
        read_timeout: read_timeout,
        write_timeout: write_timeout,
        compression: compression,
        compression_threshold: compression_threshold,
      }
    end

    # Creates a duplicate configuration
    #
    # @return [Configuration] a new configuration with the same settings
    def dup
      new_config = Configuration.new
      instance_variables.each do |var|
        value = instance_variable_get(var)
        begin
          new_config.instance_variable_set(var, value.dup)
        rescue StandardError
          value
        end
      end
      new_config
    end

    # Validates the configuration
    #
    # @raise [ConfigurationError] if the configuration is invalid
    # @return [Boolean] true if valid
    def validate!
      raise ConfigurationError, "host is required" if host.nil? || host.empty?
      raise ConfigurationError, "port must be a positive integer" unless port.is_a?(Integer) && port.positive?
      raise ConfigurationError, "database is required" if database.nil? || database.empty?
      raise ConfigurationError, "pool_size must be at least 1" unless pool_size >= 1

      true
    end
  end
end
