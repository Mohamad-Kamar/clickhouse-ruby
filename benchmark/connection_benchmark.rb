#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark for ClickhouseRuby connection performance
#
# This benchmark measures:
# - Connection establishment time (target: < 100ms)
# - Connection pool performance
# - Ping latency
# - Concurrent connection handling
#
# Usage:
#   ruby benchmark/connection_benchmark.rb
#   CLICKHOUSE_HOST=my-host ruby benchmark/connection_benchmark.rb

require_relative "benchmark_helper"

module ConnectionBenchmark
  class << self
    def run
      BenchmarkHelper.print_header("Connection Performance")
      BenchmarkHelper.ensure_clickhouse_available!

      results = []

      # Benchmark 1: Connection establishment (cold start)
      puts "\n--- Benchmark 1: Connection Establishment (Cold Start) ---"
      result = measure_cold_connection_time
      result[:target_key] = :connection_establishment_ms
      results << result
      BenchmarkHelper.print_result(result, target_key: :connection_establishment_ms)

      # Benchmark 2: Ping latency (warm connection)
      puts "\n--- Benchmark 2: Ping Latency (Warm Connection) ---"
      result = BenchmarkHelper.measure_latency("Ping (warm)", iterations: 100) do
        BenchmarkHelper.client.ping
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 3: Connection pool checkout/checkin
      puts "\n--- Benchmark 3: Connection Pool Checkout/Checkin ---"
      result = BenchmarkHelper.measure_latency("Pool checkout/checkin", iterations: 100) do
        BenchmarkHelper.client.pool.with_connection(&:ping)
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 4: Connection reuse vs new connection
      puts "\n--- Benchmark 4: Connection Reuse vs New Connection ---"
      BenchmarkHelper.compare_benchmarks(warmup: 1, time: 5) do |x|
        x.report("Reused connection (pool)") do
          BenchmarkHelper.client.pool.with_connection do |conn|
            conn.get("/ping")
          end
        end

        x.report("New connection each time") do
          config = build_connection_config
          conn = ClickhouseRuby::Connection.new(**config)
          conn.connect
          conn.get("/ping")
          conn.disconnect
        end
      end

      # Benchmark 5: Pool under load
      puts "\n--- Benchmark 5: Pool Under Load (Sequential) ---"
      pool_load_result = measure_pool_under_load
      results << pool_load_result
      BenchmarkHelper.print_result(pool_load_result)

      # Benchmark 6: Connection pool scaling
      puts "\n--- Benchmark 6: Pool Size Comparison ---"
      compare_pool_sizes

      # Benchmark 7: Health check performance
      puts "\n--- Benchmark 7: Health Check Performance ---"
      result = BenchmarkHelper.measure_latency("Pool health check", iterations: 50) do
        BenchmarkHelper.client.pool.health_check
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 8: Connection throughput
      puts "\n--- Benchmark 8: Connection Throughput ---"
      throughput = BenchmarkHelper.measure_throughput("Connections per second", duration_seconds: 5) do
        BenchmarkHelper.client.pool.with_connection do |conn|
          conn.get("/ping")
        end
      end
      results << throughput
      BenchmarkHelper.print_result(throughput)

      # Print pool statistics
      puts "\n--- Connection Pool Statistics ---"
      stats = BenchmarkHelper.client.pool_stats
      puts "  Pool size: #{stats[:size]}"
      puts "  Available: #{stats[:available]}"
      puts "  In use: #{stats[:in_use]}"
      puts "  Total connections: #{stats[:total_connections]}"
      puts "  Total checkouts: #{stats[:total_checkouts]}"
      puts "  Total timeouts: #{stats[:total_timeouts]}"
      puts "  Uptime: #{stats[:uptime_seconds].round(2)} seconds"

      BenchmarkHelper.print_summary(results.select { |r| r[:target_key] })

      # Additional recommendations
      puts "\n#{"=" * 60}"
      puts "RECOMMENDATIONS"
      puts "=" * 60
      puts "  - Use connection pooling for best performance"
      puts "  - Pool size of 5-10 is optimal for most workloads"
      puts "  - Keep connections warm with periodic health checks"
      puts "=" * 60
    end

    private

    def build_connection_config
      {
        host: ENV.fetch("CLICKHOUSE_HOST", "localhost"),
        port: ENV.fetch("CLICKHOUSE_PORT", 8123).to_i,
        database: ENV.fetch("CLICKHOUSE_DATABASE", "default"),
        username: ENV.fetch("CLICKHOUSE_USER", "default"),
        password: ENV.fetch("CLICKHOUSE_PASSWORD", nil),
        use_ssl: ENV.fetch("CLICKHOUSE_SSL", "false") == "true",
        connect_timeout: 5,
        read_timeout: 30,
      }
    end

    def measure_cold_connection_time
      times = []
      iterations = 20

      iterations.times do
        # Create a new connection (not from pool)
        config = build_connection_config
        conn = ClickhouseRuby::Connection.new(**config)

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        conn.connect
        conn.ping
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
        times << elapsed

        conn.disconnect
      end

      sorted = times.sort
      {
        label: "Connection establishment",
        iterations: iterations,
        min_ms: sorted.first.round(2),
        max_ms: sorted.last.round(2),
        avg_ms: (times.sum / times.size).round(2),
        median_ms: percentile(sorted, 50).round(2),
        p95_ms: percentile(sorted, 95).round(2),
        p99_ms: percentile(sorted, 99).round(2),
      }
    end

    def measure_pool_under_load
      # Simulate load: 1000 operations using the pool
      operations = 1000
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      operations.times do
        BenchmarkHelper.client.execute("SELECT 1")
      end

      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000

      {
        label: "Pool under load (1000 ops)",
        operations: operations,
        total_ms: elapsed.round(2),
        avg_ms: (elapsed / operations).round(2),
      }
    end

    def compare_pool_sizes
      [1, 5, 10].each do |pool_size|
        config = ClickhouseRuby::Configuration.new
        config.host = ENV.fetch("CLICKHOUSE_HOST", "localhost")
        config.port = ENV.fetch("CLICKHOUSE_PORT", 8123).to_i
        config.database = ENV.fetch("CLICKHOUSE_DATABASE", "default")
        config.username = ENV.fetch("CLICKHOUSE_USER", "default")
        config.password = ENV.fetch("CLICKHOUSE_PASSWORD", nil)
        config.ssl = ENV.fetch("CLICKHOUSE_SSL", "false") == "true"
        config.pool_size = pool_size
        config.connect_timeout = 5
        config.read_timeout = 30

        client = ClickhouseRuby::Client.new(config)

        # Warm up
        10.times { client.execute("SELECT 1") }

        # Measure
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        100.times { client.execute("SELECT 1") }
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000

        puts "  Pool size #{pool_size}: #{(elapsed / 100).round(2)} ms avg per query"

        client.close
      end
    end

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
  end
end

# Run the benchmark if this file is executed directly
ConnectionBenchmark.run if __FILE__ == $PROGRAM_NAME
