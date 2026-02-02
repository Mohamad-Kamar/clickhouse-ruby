# frozen_string_literal: true

# Benchmark helper providing utilities for performance testing ClickhouseRuby
#
# Usage:
#   require_relative "benchmark_helper"
#   BenchmarkHelper.run_benchmark("SELECT 1") { client.execute("SELECT 1") }

require "bundler/setup"
require "clickhouse_ruby"
require "benchmark/ips"

# Helper module for benchmarking ClickhouseRuby operations
module BenchmarkHelper
  # Performance targets from MVP.md
  TARGETS = {
    connection_establishment_ms: 100,  # Connection establishment < 100ms
    simple_select_overhead_ms: 50,     # Simple SELECT overhead < 50ms
    bulk_insert_10k_seconds: 1.0,      # Bulk INSERT (10K rows) < 1 second
  }.freeze

  # Default benchmark configuration
  DEFAULT_WARMUP = 2
  DEFAULT_TIME = 5

  class << self
    # Returns a configured client for benchmarking
    #
    # @return [ClickhouseRuby::Client] a benchmark client
    def client
      @client ||= begin
        configure_client
        ClickhouseRuby.client
      end
    end

    # Configures the ClickhouseRuby client for benchmarking
    #
    # @return [void]
    def configure_client
      ClickhouseRuby.configure do |config|
        config.host = ENV.fetch("CLICKHOUSE_HOST", "localhost")
        config.port = ENV.fetch("CLICKHOUSE_PORT", 8123).to_i
        config.database = ENV.fetch("CLICKHOUSE_DATABASE", "default")
        config.username = ENV.fetch("CLICKHOUSE_USER", "default")
        config.password = ENV.fetch("CLICKHOUSE_PASSWORD", nil)
        config.ssl = ENV.fetch("CLICKHOUSE_SSL", "false") == "true"
        config.connect_timeout = 5
        config.read_timeout = 30
        config.pool_size = 5
      end
    end

    # Runs a benchmark using benchmark-ips
    #
    # @param label [String] benchmark label
    # @param warmup [Integer] warmup time in seconds
    # @param time [Integer] benchmark time in seconds
    # @yield the block to benchmark
    # @return [Benchmark::IPS::Report] benchmark results
    def run_benchmark(label, warmup: DEFAULT_WARMUP, time: DEFAULT_TIME, &block)
      Benchmark.ips do |x|
        x.config(warmup: warmup, time: time)
        x.report(label, &block)
      end
    end

    # Runs multiple benchmarks for comparison
    #
    # @param warmup [Integer] warmup time in seconds
    # @param time [Integer] benchmark time in seconds
    # @yield [Benchmark::IPS::Job] the benchmark job for adding reports
    # @return [Benchmark::IPS::Report] benchmark results
    def compare_benchmarks(warmup: DEFAULT_WARMUP, time: DEFAULT_TIME)
      Benchmark.ips do |x|
        x.config(warmup: warmup, time: time)
        yield x
        x.compare!
      end
    end

    # Measures latency statistics for an operation
    #
    # @param label [String] measurement label
    # @param iterations [Integer] number of iterations
    # @yield the block to measure
    # @return [Hash] latency statistics (min_ms, max_ms, avg_ms, median_ms, p95_ms, p99_ms)
    def measure_latency(label, iterations: 10)
      times = []
      iterations.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
        times << ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000)
      end

      sorted = times.sort
      {
        label: label,
        iterations: iterations,
        min_ms: sorted.first.round(2),
        max_ms: sorted.last.round(2),
        avg_ms: (times.sum / times.size).round(2),
        median_ms: percentile(sorted, 50).round(2),
        p95_ms: percentile(sorted, 95).round(2),
        p99_ms: percentile(sorted, 99).round(2),
      }
    end

    # Measures throughput for an operation
    #
    # @param label [String] measurement label
    # @param duration_seconds [Integer] how long to run
    # @yield the block to measure
    # @return [Hash] throughput statistics
    def measure_throughput(label, duration_seconds: 5)
      count = 0
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end_time = start_time + duration_seconds

      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < end_time
        yield
        count += 1
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      {
        label: label,
        total_operations: count,
        duration_seconds: elapsed.round(2),
        ops_per_second: (count / elapsed).round(2),
      }
    end

    # Checks if a measurement meets its target
    #
    # @param measurement_ms [Float] the measured value in milliseconds
    # @param target_key [Symbol] the target key from TARGETS
    # @return [Boolean] true if within target
    def meets_target?(measurement_ms, target_key)
      target = TARGETS[target_key]
      return false unless target

      measurement_ms <= target
    end

    # Prints a formatted benchmark result
    #
    # @param result [Hash] result from measure_latency or measure_throughput
    # @param target_key [Symbol, nil] optional target to compare against
    # @return [void]
    def print_result(result, target_key: nil)
      puts "\n=== #{result[:label]} ==="

      if result[:avg_ms]
        # Latency result
        puts "  Iterations: #{result[:iterations]}"
        puts "  Min:    #{result[:min_ms]} ms"
        puts "  Max:    #{result[:max_ms]} ms"
        puts "  Avg:    #{result[:avg_ms]} ms"
        puts "  Median: #{result[:median_ms]} ms"
        puts "  P95:    #{result[:p95_ms]} ms"
        puts "  P99:    #{result[:p99_ms]} ms"

        if target_key
          target = TARGETS[target_key]
          status = meets_target?(result[:avg_ms], target_key) ? "PASS" : "FAIL"
          puts "  Target: #{target} ms [#{status}]"
        end
      elsif result[:ops_per_second]
        # Throughput result
        puts "  Total operations: #{result[:total_operations]}"
        puts "  Duration: #{result[:duration_seconds]} seconds"
        puts "  Throughput: #{result[:ops_per_second]} ops/sec"
      end
    end

    # Generates test data for insert benchmarks
    #
    # @param count [Integer] number of rows to generate
    # @param columns [Hash] column definitions (name => type)
    # @return [Array<Hash>] array of row data
    def generate_test_data(count, columns = nil)
      columns ||= default_test_columns
      (1..count).map do |i|
        generate_row(i, columns)
      end
    end

    # Creates a test table for benchmarking
    #
    # @param table_name [String] table name
    # @param columns [Hash] column definitions
    # @param engine [String] table engine
    # @return [void]
    def create_benchmark_table(table_name, columns: nil, engine: "MergeTree")
      columns ||= default_test_columns
      column_defs = columns.map { |name, type| "#{name} #{type}" }.join(", ")

      client.command("DROP TABLE IF EXISTS #{table_name}")
      client.command(<<~SQL)
        CREATE TABLE #{table_name} (
          #{column_defs}
        ) ENGINE = #{engine}
        ORDER BY id
      SQL
    end

    # Drops a benchmark table
    #
    # @param table_name [String] table name
    # @return [void]
    def drop_benchmark_table(table_name)
      client.command("DROP TABLE IF EXISTS #{table_name}")
    end

    # Truncates a benchmark table
    #
    # @param table_name [String] table name
    # @return [void]
    def truncate_benchmark_table(table_name)
      client.command("TRUNCATE TABLE IF EXISTS #{table_name}")
    end

    # Ensures ClickHouse is available before benchmarking
    #
    # @return [Boolean] true if ClickHouse is reachable
    # @raise [RuntimeError] if ClickHouse is not available
    def ensure_clickhouse_available!
      unless client.ping
        raise "ClickHouse is not available at #{ENV.fetch("CLICKHOUSE_HOST",
                                                          "localhost",)}:#{ENV.fetch("CLICKHOUSE_PORT", 8123)}. " \
              "Please start ClickHouse before running benchmarks."
      end

      puts "ClickHouse connection verified: #{client.server_version}"
      true
    end

    # Prints benchmark header with system info
    #
    # @param benchmark_name [String] name of the benchmark
    # @return [void]
    def print_header(benchmark_name)
      puts "=" * 60
      puts "ClickhouseRuby Benchmark: #{benchmark_name}"
      puts "=" * 60
      puts "Ruby version: #{RUBY_VERSION}"
      puts "ClickHouse host: #{ENV.fetch("CLICKHOUSE_HOST", "localhost")}"
      puts "ClickHouse port: #{ENV.fetch("CLICKHOUSE_PORT", 8123)}"
      puts "Time: #{Time.now}"
      puts "=" * 60
    end

    # Prints performance targets summary
    #
    # @param results [Array<Hash>] array of results with :label, :avg_ms or :duration_seconds
    # @return [void]
    def print_summary(results)
      puts "\n#{"=" * 60}"
      puts "SUMMARY"
      puts "=" * 60

      pass_count = 0
      fail_count = 0

      results.each do |result|
        target_key = result[:target_key]
        next unless target_key

        value = result[:avg_ms] || (result[:duration_seconds] * 1000)
        target = TARGETS[target_key]
        status = value <= target

        if status
          pass_count += 1
          puts "  [PASS] #{result[:label]}: #{value.round(2)} ms (target: #{target} ms)"
        else
          fail_count += 1
          puts "  [FAIL] #{result[:label]}: #{value.round(2)} ms (target: #{target} ms)"
        end
      end

      puts "-" * 60
      puts "Total: #{pass_count} passed, #{fail_count} failed"
      puts "=" * 60
    end

    private

    # Calculates percentile value from sorted array
    #
    # @param sorted_array [Array<Float>] sorted array of values
    # @param percentile [Integer] percentile to calculate (0-100)
    # @return [Float] percentile value
    def percentile(sorted_array, percentile)
      return sorted_array.first if sorted_array.size == 1

      k = (percentile / 100.0) * (sorted_array.size - 1)
      f = k.floor
      c = k.ceil

      if f == c
        sorted_array[f]
      else
        (sorted_array[f] * (c - k)) + (sorted_array[c] * (k - f))
      end
    end

    # Default test columns for insert benchmarks
    #
    # @return [Hash] column definitions
    def default_test_columns
      {
        "id" => "UInt64",
        "name" => "String",
        "value" => "Float64",
        "created_at" => "DateTime",
      }
    end

    # Generates a single row of test data
    #
    # @param id [Integer] row ID
    # @param columns [Hash] column definitions
    # @return [Hash] row data
    def generate_row(id, columns)
      row = {}
      columns.each do |name, type|
        row[name] = generate_value(name, type, id)
      end
      row
    end

    # Generates a value for a column
    #
    # @param name [String] column name
    # @param type [String] column type
    # @param id [Integer] row ID for deterministic generation
    # @return [Object] generated value
    def generate_value(name, type, id)
      case type
      when /^UInt/, /^Int/
        id
      when "String"
        "#{name}_value_#{id}"
      when "Float32", "Float64"
        id * 1.5
      when "DateTime"
        Time.now
      when "Date"
        Date.today
      when /^Array/
        [id, id + 1, id + 2]
      else
        "value_#{id}"
      end
    end
  end
end
