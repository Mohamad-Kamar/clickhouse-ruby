# frozen_string_literal: true

require "json"
require "uri"
require "net/http"
require "zlib"

module ClickhouseRuby
  # Memory-efficient streaming result for large queries
  #
  # StreamingResult provides an Enumerable interface for processing ClickHouse
  # query results without loading all rows into memory. Rows are parsed
  # line-by-line as they arrive from the server.
  #
  # Features:
  # - Enumerable interface for chainable operations
  # - Lazy evaluation (no data loaded until iterated)
  # - Support for gzip decompression
  # - Progress callbacks
  # - Batch processing
  #
  # @example Basic usage
  #   client.stream_execute('SELECT * FROM huge_table').each do |row|
  #     process(row)
  #   end
  #
  # @example Lazy enumeration with filtering
  #   result = client.stream_execute('SELECT * FROM huge_table')
  #     .lazy
  #     .select { |row| row['active'] == 1 }
  #     .take(100)
  #     .to_a
  #
  # @example Batch processing
  #   result.each_batch(size: 1000) do |batch|
  #     insert_into_cache(batch)
  #   end
  #
  class StreamingResult
    include Enumerable

    # Creates a new streaming result
    #
    # @param connection [Connection] the ClickHouse connection
    # @param sql [String] the SQL query to execute
    # @param format [String] response format (default: JSONEachRow)
    # @param compression [String, nil] compression algorithm ('gzip' or nil)
    def initialize(connection, sql, format: "JSONEachRow", compression: nil)
      @connection = connection
      @sql = sql
      @format = format
      @compression = compression
      @progress_callback = nil
    end

    # Sets a callback for progress updates
    #
    # ClickHouse sends progress headers during execution:
    # X-ClickHouse-Progress: {"read_rows":"1000","read_bytes":"50000"}
    #
    # @yield [Hash] progress data
    # @return [self] for method chaining
    #
    # @example
    #   result.on_progress do |progress|
    #     puts "Processed #{progress['read_rows']} rows"
    #   end.each { |row| ... }
    def on_progress(&block)
      @progress_callback = block
      self
    end

    # Iterates over each row in the result
    #
    # Returns an Enumerator if no block is given, allowing for lazy evaluation.
    #
    # @yield [Hash] each row as a parsed JSON object
    # @return [Enumerator] if no block given, otherwise nil
    #
    # @example With block
    #   result.each { |row| puts row['id'] }
    #
    # @example Returns enumerator without block
    #   enumerator = result.each
    def each(&block) # rubocop:disable Naming/BlockForwarding
      return enum_for(__method__) unless block_given?

      stream_query(&block) # rubocop:disable Naming/BlockForwarding
    end

    # Iterates over rows in batches
    #
    # Useful for batch processing (e.g., bulk database operations).
    # The final batch may be smaller than the specified size.
    #
    # @param size [Integer] batch size (default: 1000)
    # @yield [Array<Hash>] each batch of rows
    # @return [Enumerator] if no block given, otherwise nil
    #
    # @example
    #   result.each_batch(size: 500) do |batch|
    #     insert_batch(batch)
    #   end
    def each_batch(size: 1000)
      return enum_for(__method__, size: size) unless block_given?

      batch = []
      each do |row|
        batch << row
        if batch.size >= size
          yield batch
          batch = []
        end
      end
      yield batch if batch.any?
    end

    private

    # Executes the streaming query
    #
    # @yield [Hash] each parsed row
    # @return [void]
    def stream_query(&block) # rubocop:disable Naming/BlockForwarding
      uri = build_uri
      request = build_request(uri)

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: @connection.use_ssl,
        ssl_version: :TLSv1_2, # rubocop:disable Naming/VariableNumber
      ) do |http|
        http.request(request) do |response|
          check_response_status(response)
          handle_progress(response)

          parse_streaming_body(response, &block) # rubocop:disable Naming/BlockForwarding
        end
      end
    end

    # Builds the request URI
    #
    # @return [URI] the request URI with query parameters
    def build_uri
      uri = URI("http#{"s" if @connection.use_ssl}://#{@connection.host}:#{@connection.port}/")
      params = {
        "database" => @connection.database,
        "query" => "#{@sql} FORMAT #{@format}",
      }
      params["enable_http_compression"] = "1" if @compression
      uri.query = URI.encode_www_form(params)
      uri
    end

    # Builds the HTTP request
    #
    # @param uri [URI] the request URI
    # @return [Net::HTTP::Get] the HTTP request
    def build_request(uri)
      request = Net::HTTP::Get.new(uri)
      request["Accept-Encoding"] = "gzip" if @compression
      request
    end

    # Checks the HTTP response status
    #
    # @param response [Net::HTTPResponse] the HTTP response
    # @return [void]
    # @raise [QueryError] if status is not 200
    def check_response_status(response)
      return if response.code == "200"

      body = response.body || ""
      raise_clickhouse_error(response, body)
    end

    # Handles progress header if callback is set
    #
    # @param response [Net::HTTPResponse] the HTTP response
    # @return [void]
    def handle_progress(response)
      return unless @progress_callback

      progress = response["X-ClickHouse-Progress"]
      return unless progress

      @progress_callback.call(JSON.parse(progress))
    end

    # Parses the streaming response body
    #
    # Handles:
    # - Chunked transfer encoding
    # - Incomplete line buffering
    # - Gzip decompression if enabled
    #
    # @param response [Net::HTTPResponse] the HTTP response
    # @yield [Hash] each parsed row
    # @return [void]
    def parse_streaming_body(response) # rubocop:disable Metrics/CyclomaticComplexity
      decompressor = create_decompressor(response)
      buffer = ""

      response.read_body do |chunk|
        data = decompressor ? decompressor.inflate(chunk) : chunk
        buffer += data

        # Process complete lines
        while buffer.include?("\n")
          line, buffer = buffer.split("\n", 2)
          next if line.empty?

          row = parse_row(line)
          yield row if row
        end
      end

      # Finalize decompression
      if decompressor
        buffer += decompressor.finish
        decompressor.close
      end

      # Process remaining buffer (last line may not end with \n)
      return if buffer.strip.empty?

      row = parse_row(buffer)
      yield row if row
    end

    # Creates a decompressor based on Content-Encoding header
    #
    # @param response [Net::HTTPResponse] the HTTP response
    # @return [Zlib::Inflate, nil] decompressor or nil
    def create_decompressor(response)
      case response["Content-Encoding"]
      when "gzip"
        Zlib::Inflate.new(16 + Zlib::MAX_WBITS)
      end
    end

    # Parses a single row from JSON
    #
    # @param line [String] JSON line
    # @return [Hash, nil] parsed row or nil
    # @raise [QueryError] if line contains error
    def parse_row(line)
      data = JSON.parse(line)

      # Check for error in stream
      if data["exception"]
        raise QueryError.new(
          data["exception"]["message"],
          code: data["exception"]["code"],
        )
      end

      data
    rescue JSON::ParserError => e
      raise QueryError.new(
        "Failed to parse streaming response: #{e.message}",
        original_error: e,
      )
    end

    # Raises a ClickHouse error
    #
    # @param response [Net::HTTPResponse] the HTTP response
    # @param body [String] response body
    # @return [void]
    # @raise [QueryError] always raises
    def raise_clickhouse_error(response, body)
      code = extract_error_code(body)
      message = extract_error_message(body)

      error_class = ClickhouseRuby.error_class_for_code(code)

      raise error_class.new(
        message,
        code: code,
        http_status: response.code,
        sql: @sql,
      )
    end

    # Extracts ClickHouse error code from response body
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
      if body =~ /DB::Exception:\s*(.+?)(?:\s*\(version|$)/m
        ::Regexp.last_match(1).strip
      else
        body.strip.empty? ? "Unknown ClickHouse error" : body.strip
      end
    end
  end
end
