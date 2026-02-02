# frozen_string_literal: true

require "json"
require "uri"
require "bigdecimal"

module ClickhouseRuby
  # Main HTTP client for ClickHouse communication
  #
  # The Client provides a high-level interface for executing queries
  # and inserting data into ClickHouse. It handles:
  # - Connection pooling for performance
  # - Automatic format handling (JSONCompact for queries)
  # - Proper error handling with rich context
  # - Bulk inserts with JSONEachRow format
  #
  # CRITICAL: This client ALWAYS checks HTTP status codes before parsing
  # response bodies. This prevents the silent error bug found in
  # clickhouse-activerecord (issue #230).
  #
  # @example Basic usage
  #   config = ClickhouseRuby::Configuration.new
  #   config.host = 'localhost'
  #   client = ClickhouseRuby::Client.new(config)
  #
  #   result = client.execute('SELECT * FROM users LIMIT 10')
  #   result.each { |row| puts row['name'] }
  #
  # @example With settings
  #   result = client.execute(
  #     'SELECT * FROM large_table',
  #     settings: { max_execution_time: 120 }
  #   )
  #
  # @example Bulk insert
  #   client.insert('events', [
  #     { id: 1, event: 'click', timestamp: Time.now },
  #     { id: 2, event: 'view', timestamp: Time.now }
  #   ])
  #
  class Client
    # Default response format for queries
    DEFAULT_FORMAT = "JSONCompact"

    # Format for bulk inserts (5x faster than VALUES)
    INSERT_FORMAT = "JSONEachRow"

    # @return [Configuration] the client configuration
    attr_reader :config

    # @return [ConnectionPool] the connection pool
    attr_reader :pool

    # @return [RetryHandler] the retry handler
    attr_reader :retry_handler

    # Creates a new Client
    #
    # @param config [Configuration] connection configuration
    # @raise [ConfigurationError] if configuration is invalid
    def initialize(config)
      @config = config
      @config.validate!
      @pool = ConnectionPool.new(config)
      @logger = config.logger
      @default_settings = config.default_settings || {}
      @retry_handler = RetryHandler.new(
        max_attempts: config.max_retries,
        initial_backoff: config.initial_backoff,
        max_backoff: config.max_backoff,
        multiplier: config.backoff_multiplier,
        jitter: config.retry_jitter,
      )
    end

    # Executes a SQL query and returns results
    #
    # @param sql [String] the SQL query to execute
    # @param settings [Hash] ClickHouse settings for this query
    # @param format [String] response format (default: JSONCompact)
    # @return [Result] query results
    # @raise [QueryError] if query fails
    # @raise [ConnectionError] if connection fails
    #
    # @example
    #   result = client.execute('SELECT count() FROM users')
    #   puts result.first['count()']
    #
    # @example With settings
    #   result = client.execute(
    #     'SELECT * FROM events',
    #     settings: { max_rows_to_read: 1_000_000 }
    #   )
    def execute(sql, settings: {}, format: DEFAULT_FORMAT)
      @retry_handler.with_retry(idempotent: true) do
        execute_internal(sql, settings: settings, format: format)
      end
    end

    # Executes a command (INSERT, CREATE, DROP, etc.) that doesn't return data
    #
    # @param sql [String] the SQL command to execute
    # @param settings [Hash] ClickHouse settings
    # @return [Boolean] true if successful
    # @raise [QueryError] if command fails
    #
    # @example
    #   client.command('CREATE TABLE test (id UInt64) ENGINE = Memory')
    #   client.command('DROP TABLE test')
    def command(sql, settings: {})
      params = build_query_params(settings)
      execute_request(sql, params)
      true
    end

    # Inserts multiple rows using bulk insert (JSONEachRow format)
    #
    # This is significantly faster than INSERT ... VALUES for large datasets.
    # The data is sent in JSONEachRow format which ClickHouse can parse
    # efficiently.
    #
    # @param table [String] the table name
    # @param rows [Array<Hash>] array of row hashes
    # @param columns [Array<String>, nil] column names (inferred from first row if nil)
    # @param settings [Hash] ClickHouse settings
    # @param format [Symbol] insert format (:json_each_row is default and recommended)
    # @return [Boolean] true if successful
    # @raise [QueryError] if insert fails
    # @raise [ArgumentError] if rows is empty
    #
    # @example
    #   client.insert('events', [
    #     { id: 1, name: 'click' },
    #     { id: 2, name: 'view' }
    #   ])
    #
    # @example With explicit columns
    #   client.insert('events', [
    #     { id: 1, name: 'click', extra: 'ignored' },
    #   ], columns: ['id', 'name'])
    def insert(table, rows, columns: nil, settings: {}, format: :json_each_row)
      raise ArgumentError, "rows cannot be empty" if rows.nil? || rows.empty?

      @retry_handler.with_retry(idempotent: false) do |query_id|
        settings_with_id = settings.merge(query_id: query_id)
        insert_internal(table, rows, columns: columns, settings: settings_with_id, format: format)
      end
    end

    # Checks if the ClickHouse server is reachable
    #
    # @return [Boolean] true if server responds to ping
    def ping
      @pool.with_connection(&:ping)
    rescue ClickhouseRuby::ConnectionError, ClickhouseRuby::ConnectionTimeout,
           ClickhouseRuby::PoolTimeout, SystemCallError, SocketError,
           Net::OpenTimeout, Net::ReadTimeout
      false
    end

    # Returns the ClickHouse server version
    #
    # @return [String] version string
    # @raise [QueryError] if query fails
    def server_version
      result = execute("SELECT version() AS version")
      result.first["version"]
    end

    # Closes all connections in the pool
    #
    # Call this when shutting down to clean up resources.
    #
    # @return [void]
    def close
      @pool.shutdown
    end
    alias disconnect close

    # Returns pool statistics
    #
    # @return [Hash] pool stats
    def pool_stats
      @pool.stats
    end

    # Returns a streaming result for memory-efficient processing
    #
    # Useful for queries that return large result sets. Results are parsed
    # line-by-line as they arrive from the server, keeping memory usage constant.
    #
    # @param sql [String] the SQL query to execute
    # @param settings [Hash] ClickHouse settings for this query
    # @return [StreamingResult] the streaming result
    #
    # @example
    #   result = client.stream_execute('SELECT * FROM huge_table')
    #   result.each { |row| process(row) }
    #
    # @example Lazy enumeration
    #   client.stream_execute('SELECT * FROM huge_table')
    #     .lazy
    #     .select { |row| row['active'] == 1 }
    #     .take(100)
    #     .to_a
    def stream_execute(sql, settings: {})
      # Create dedicated connection (not from pool)
      connection = Connection.new(@config.to_connection_options)

      StreamingResult.new(
        connection,
        sql,
        compression: @config.compression,
      )
    end

    # Convenience method for iterating over rows one at a time
    #
    # Equivalent to stream_execute(sql).each(&block)
    #
    # @param sql [String] the SQL query to execute
    # @param settings [Hash] ClickHouse settings
    # @yield [Hash] each row
    # @return [Enumerator] if no block given, otherwise nil
    #
    # @example
    #   client.each_row('SELECT * FROM events') do |row|
    #     process(row)
    #   end
    def each_row(sql, settings: {}, &block)
      stream_execute(sql, settings: settings).each(&block)
    end

    # Convenience method for batch processing
    #
    # Equivalent to stream_execute(sql).each_batch(size: batch_size, &block)
    #
    # @param sql [String] the SQL query to execute
    # @param batch_size [Integer] number of rows per batch
    # @param settings [Hash] ClickHouse settings
    # @yield [Array<Hash>] each batch of rows
    # @return [Enumerator] if no block given, otherwise nil
    #
    # @example
    #   client.each_batch('SELECT * FROM events', batch_size: 500) do |batch|
    #     insert_into_cache(batch)
    #   end
    def each_batch(sql, batch_size: 1000, settings: {}, &block)
      stream_execute(sql, settings: settings).each_batch(size: batch_size, &block)
    end

    private

    # Internal execute without retry wrapper
    #
    # @param sql [String] the SQL query to execute
    # @param settings [Hash] ClickHouse settings for this query
    # @param format [String] response format (default: JSONCompact)
    # @return [Result] query results
    def execute_internal(sql, settings: {}, format: DEFAULT_FORMAT)
      # Build the query with format
      query_with_format = "#{sql.strip} FORMAT #{format}"

      # Build query parameters
      params = build_query_params(settings)

      # Execute via connection pool
      response = execute_request(query_with_format, params)

      # Parse response based on format
      parse_response(response, sql, format)
    end

    # Internal insert without retry wrapper
    #
    # @param table [String] the table name
    # @param rows [Array<Hash>] array of row hashes
    # @param columns [Array<String>, nil] column names
    # @param settings [Hash] ClickHouse settings (may include query_id)
    # @param format [Symbol] insert format
    # @return [Boolean] true if successful
    def insert_internal(table, rows, columns: nil, settings: {}, format: :json_each_row)
      # Determine columns from first row if not specified
      columns ||= rows.first.keys.map(&:to_s)

      # Build INSERT statement
      columns_str = columns.map { |c| quote_identifier(c) }.join(", ")
      sql = "INSERT INTO #{quote_identifier(table)} (#{columns_str}) FORMAT #{INSERT_FORMAT}"

      # Build JSON body
      body = rows.map do |row|
        row_data = {}
        columns.each do |col|
          key = col.to_s
          value = row[col] || row[col.to_sym]
          row_data[key] = serialize_value(value)
        end
        JSON.generate(row_data)
      end.join("\n")

      # Build params and execute
      params = build_query_params(settings)
      path = build_path(params)

      @pool.with_connection do |conn|
        log_query(sql) if @logger

        response = conn.post("#{path}&query=#{URI.encode_www_form_component(sql)}", body, {
          "Content-Type" => "application/json",
        },)

        handle_response(response, sql)
      end

      true
    end

    # Builds query parameters including database and settings
    #
    # @param settings [Hash] query-specific settings
    # @return [Hash] all query parameters
    def build_query_params(settings = {})
      params = {
        "database" => @config.database,
      }

      # Add compression parameter if enabled
      params["enable_http_compression"] = "1" if @config.compression_enabled?

      # Merge default settings and query-specific settings
      all_settings = @default_settings.merge(settings)
      all_settings.each do |key, value|
        params[key.to_s] = value.to_s
      end

      params
    end

    # Builds the request path with query parameters
    #
    # @param params [Hash] query parameters
    # @return [String] the path with query string
    def build_path(params)
      query_string = params.map { |k, v| "#{k}=#{URI.encode_www_form_component(v)}" }.join("&")
      "/?#{query_string}"
    end

    # Executes a request through the connection pool
    #
    # @param sql [String] the SQL to execute
    # @param params [Hash] query parameters
    # @return [Net::HTTPResponse] the response
    def execute_request(sql, params)
      path = build_path(params)

      @pool.with_connection do |conn|
        log_query(sql) if @logger

        response = conn.post(path, sql)
        handle_response(response, sql)
        response
      end
    end

    # Handles HTTP response with CRITICAL status check
    #
    # IMPORTANT: This method ALWAYS checks status code FIRST before
    # attempting to parse the body. This prevents the silent failure
    # bug in clickhouse-activerecord where DELETE operations fail
    # without raising errors.
    #
    # @param response [Net::HTTPResponse] the HTTP response
    # @param sql [String] the SQL that was executed (for error context)
    # @return [void]
    # @raise [QueryError] if response indicates an error
    def handle_response(response, sql)
      # CRITICAL: Check status FIRST - never silently ignore errors
      return if response.code == "200"

      raise_clickhouse_error(response, sql)

      # Response is successful - caller can now safely parse body
    end

    # Raises an appropriate ClickHouse error with full context
    #
    # Extracts error code and message from response body and
    # maps to the appropriate error class.
    #
    # @param response [Net::HTTPResponse] the error response
    # @param sql [String] the SQL that failed
    # @raise [QueryError] always raises
    def raise_clickhouse_error(response, sql)
      body = response.body || ""
      code = extract_error_code(body)
      message = extract_error_message(body)

      # Get the appropriate error class based on ClickHouse error code
      error_class = ClickhouseRuby.error_class_for_code(code)

      log_error(message, code, response.code, sql) if @logger

      raise error_class.new(
        message,
        code: code,
        http_status: response.code,
        sql: truncate_sql(sql),
      )
    end

    # Extracts ClickHouse error code from response body
    #
    # ClickHouse errors follow the pattern: "Code: 60."
    #
    # @param body [String] response body
    # @return [Integer, nil] error code or nil
    def extract_error_code(body)
      match = body.match(/Code:\s*(\d+)/)
      match ? match[1].to_i : nil
    end

    # Extracts error message from response body
    #
    # @param body [String] response body
    # @return [String] error message
    def extract_error_message(body)
      # ClickHouse error format: "Code: 60. DB::Exception: Table ... doesn't exist."
      # Try to extract just the meaningful part
      if body =~ /DB::Exception:\s*(.+?)(?:\s*\(version|$)/m
        ::Regexp.last_match(1).strip
      else
        body.strip.empty? ? "Unknown ClickHouse error" : body.strip
      end
    end

    # Parses successful response based on format
    #
    # @param response [Net::HTTPResponse] the response
    # @param sql [String] original SQL (for error context)
    # @param format [String] the response format
    # @return [Result] parsed result
    def parse_response(response, sql, format)
      body = response.body

      # Empty response (for commands)
      return Result.empty if body.nil? || body.strip.empty?

      case format
      when "JSONCompact"
        parse_json_compact(body, sql)
      when "JSON"
        parse_json(body, sql)
      else
        # For unknown formats, return raw body wrapped in result
        Result.new(columns: ["result"], types: ["String"], data: [[body]])
      end
    end

    # Parses JSONCompact format response
    #
    # @param body [String] response body
    # @param sql [String] original SQL
    # @return [Result]
    def parse_json_compact(body, sql)
      data = parse_json_body(body, sql)
      Result.from_json_compact(data)
    end

    # Parses JSON format response
    #
    # @param body [String] response body
    # @param sql [String] original SQL
    # @return [Result]
    def parse_json(body, sql)
      data = parse_json_body(body, sql)

      meta = data["meta"] || []
      columns = meta.map { |m| m["name"] }
      types = meta.map { |m| m["type"] }
      rows = data["data"] || []

      # JSON format returns rows as objects, convert to arrays
      row_arrays = rows.map { |row| columns.map { |col| row[col] } }

      Result.new(
        columns: columns,
        types: types,
        data: row_arrays,
        statistics: data["statistics"] || {},
      )
    end

    # Parses JSON body with error handling
    #
    # @param body [String] JSON string
    # @param sql [String] original SQL for error context
    # @return [Hash] parsed JSON
    # @raise [QueryError] if JSON parsing fails
    def parse_json_body(body, sql)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise QueryError.new(
        "Failed to parse ClickHouse response: #{e.message}",
        sql: truncate_sql(sql),
        original_error: e,
      )
    end

    # Quotes an identifier (table or column name)
    #
    # @param identifier [String] the identifier
    # @return [String] quoted identifier
    def quote_identifier(identifier)
      # ClickHouse uses backticks for identifiers
      "`#{identifier.to_s.gsub("`", "``")}`"
    end

    # Serializes a Ruby value for JSON insertion
    #
    # @param value [Object] the value
    # @return [Object] JSON-serializable value
    def serialize_value(value)
      case value
      when Time, DateTime
        # ClickHouse expects ISO8601 format for DateTime
        value.strftime("%Y-%m-%d %H:%M:%S")
      when Date
        value.strftime("%Y-%m-%d")
      when BigDecimal
        value.to_f
      when Symbol
        value.to_s
      else
        value
      end
    end

    # Truncates SQL for error messages
    #
    # @param sql [String] the SQL
    # @param max_length [Integer] maximum length
    # @return [String] truncated SQL
    def truncate_sql(sql, max_length = 1000)
      return sql if sql.length <= max_length

      "#{sql[0, max_length]}... (truncated)"
    end

    # Logs a query if logger is configured
    #
    # @param sql [String] the SQL query
    def log_query(sql)
      return unless @logger

      case @config.log_level
      when :debug
        @logger.debug("[ClickhouseRuby] #{sql}")
      else
        @logger.info("[ClickhouseRuby] Query executed")
      end
    end

    # Logs an error if logger is configured
    #
    # @param message [String] error message
    # @param code [Integer, nil] ClickHouse error code
    # @param http_status [String] HTTP status
    # @param sql [String] the SQL that failed
    def log_error(message, code, http_status, sql)
      return unless @logger

      @logger.error(
        "[ClickhouseRuby] ClickHouse error: #{message} " \
        "(code: #{code || "unknown"}, http: #{http_status}, sql: #{truncate_sql(sql, 200)})",
      )
    end
  end
end
