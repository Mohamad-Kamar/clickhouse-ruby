# frozen_string_literal: true

require "securerandom"

module ClickhouseRuby
  # Implements retry logic with exponential backoff and jitter
  #
  # This class handles transient failures in ClickHouse connections by
  # retrying with an exponential backoff strategy and optional jitter.
  #
  # @example Basic usage
  #   handler = RetryHandler.new(max_attempts: 3)
  #   result = handler.with_retry do
  #     client.execute('SELECT * FROM users')
  #   end
  #
  # @example With idempotency flag
  #   handler.with_retry(idempotent: false) do |query_id|
  #     client.insert('events', data, settings: { query_id: query_id })
  #   end
  class RetryHandler
    # Errors that should trigger a retry
    RETRIABLE_ERRORS = [
      ConnectionError,
      ConnectionTimeout,
      ConnectionNotEstablished,
      PoolTimeout,
    ].freeze

    # HTTP status codes that should trigger a retry
    RETRIABLE_HTTP_CODES = %w[500 502 503 504 429].freeze

    # @return [Integer] maximum number of attempts
    attr_reader :max_attempts

    # @return [Float] initial backoff delay in seconds
    attr_reader :initial_backoff

    # @return [Float] maximum backoff delay in seconds
    attr_reader :max_backoff

    # @return [Float] exponential backoff multiplier
    attr_reader :multiplier

    # @return [Symbol] jitter strategy (:full, :equal, or :none)
    attr_reader :jitter

    # Creates a new RetryHandler
    #
    # @param max_attempts [Integer] maximum retry attempts (default: 3)
    # @param initial_backoff [Float] initial backoff in seconds (default: 1.0)
    # @param max_backoff [Float] maximum backoff in seconds (default: 120.0)
    # @param multiplier [Float] backoff multiplier (default: 1.6)
    # @param jitter [Symbol] jitter strategy (default: :equal)
    def initialize(
      max_attempts: 3,
      initial_backoff: 1.0,
      max_backoff: 120.0,
      multiplier: 1.6,
      jitter: :equal
    )
      @max_attempts = max_attempts
      @initial_backoff = initial_backoff
      @max_backoff = max_backoff
      @multiplier = multiplier
      @jitter = jitter
    end

    # Executes a block with retry logic
    #
    # Yields to the block with an optional query_id. If the block raises
    # a retriable error, retries with exponential backoff up to max_attempts.
    # Non-retriable errors are re-raised immediately.
    #
    # @param idempotent [Boolean] whether the operation is idempotent (default: true)
    # @param query_id [String, nil] query ID for deduplication (optional)
    # @yieldparam query_id [String] generated or provided query_id
    # @return [Object] return value from the block
    # @raise [Error] if all retries are exhausted or error is non-retriable
    #
    # @example Idempotent operation (SELECT)
    #   handler.with_retry { client.execute('SELECT * FROM users') }
    #
    # @example Non-idempotent operation (INSERT)
    #   handler.with_retry(idempotent: false) do |qid|
    #     client.insert('events', data, settings: { query_id: qid })
    #   end
    def with_retry(idempotent: true, query_id: nil)
      attempts = 0
      generated_query_id = query_id || SecureRandom.uuid

      begin
        attempts += 1
        yield(generated_query_id)
      rescue *RETRIABLE_ERRORS => e
        handle_retry(attempts, e, idempotent)
        retry
      rescue QueryError => e
        # Check if HTTP code is retriable (server error or rate limit)
        if retriable_http_error?(e)
          handle_retry(attempts, e, idempotent)
          retry
        end
        raise
      end
    end

    # Checks if an error is retriable
    #
    # @param error [Exception] the error to check
    # @return [Boolean] true if the error should trigger a retry
    def retriable?(error)
      RETRIABLE_ERRORS.any? { |klass| error.is_a?(klass) } ||
        retriable_http_error?(error)
    end

    private

    # Handles retry logic for an attempt
    #
    # @param attempts [Integer] number of attempts so far
    # @param error [Exception] the error that occurred
    # @param idempotent [Boolean] whether operation is idempotent
    # @raise [Exception] if max attempts reached
    # @return [void]
    def handle_retry(attempts, error, idempotent)
      raise error if attempts >= @max_attempts

      warn "Retrying non-idempotent operation - possible duplicates" unless idempotent

      delay = calculate_delay(attempts)
      sleep(delay)
    end

    # Calculates backoff delay with jitter
    #
    # Implements exponential backoff:
    #   base = initial_backoff * (multiplier ^ (attempt - 1))
    #   capped = min(base, max_backoff)
    #
    # Then applies jitter strategy:
    # - :full - random(0, capped)
    # - :equal - capped/2 + random(0, capped/2)
    # - :none - capped (no jitter)
    #
    # @param attempt [Integer] the attempt number (1-based)
    # @return [Float] delay in seconds
    def calculate_delay(attempt)
      base = @initial_backoff * (@multiplier**(attempt - 1))
      capped = [base, @max_backoff].min

      case @jitter
      when :full
        rand * capped
      when :none
        capped
      else
        # Default to equal jitter (both :equal and unknown values)
        (capped / 2.0) + (rand * (capped / 2.0))
      end
    end

    # Checks if an error with HTTP status is retriable
    #
    # @param error [Exception] the error to check
    # @return [Boolean] true if HTTP status indicates retriable error
    def retriable_http_error?(error)
      error.respond_to?(:http_status) &&
        RETRIABLE_HTTP_CODES.include?(error.http_status.to_s)
    end
  end
end
