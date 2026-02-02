#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark for ClickhouseRuby query performance
#
# This benchmark measures:
# - Simple SELECT overhead (target: < 50ms)
# - Query result parsing performance
# - Different result set sizes
# - Format comparison (JSONCompact vs JSON)
#
# Usage:
#   ruby benchmark/query_benchmark.rb
#   CLICKHOUSE_HOST=my-host ruby benchmark/query_benchmark.rb

require_relative "benchmark_helper"

module QueryBenchmark
  BENCHMARK_TABLE = "benchmark_query_test"

  class << self
    def run
      BenchmarkHelper.print_header("Query Performance")
      BenchmarkHelper.ensure_clickhouse_available!

      setup_test_data

      results = []

      # Benchmark 1: Simple SELECT overhead
      puts "\n--- Benchmark 1: Simple SELECT Overhead ---"
      result = BenchmarkHelper.measure_latency("SELECT 1", iterations: 100) do
        BenchmarkHelper.client.execute("SELECT 1")
      end
      result[:target_key] = :simple_select_overhead_ms
      results << result
      BenchmarkHelper.print_result(result, target_key: :simple_select_overhead_ms)

      # Benchmark 2: SELECT with small result set (100 rows)
      puts "\n--- Benchmark 2: SELECT 100 Rows ---"
      result = BenchmarkHelper.measure_latency("SELECT 100 rows", iterations: 50) do
        BenchmarkHelper.client.execute("SELECT * FROM #{BENCHMARK_TABLE} LIMIT 100")
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 3: SELECT with medium result set (1000 rows)
      puts "\n--- Benchmark 3: SELECT 1000 Rows ---"
      result = BenchmarkHelper.measure_latency("SELECT 1000 rows", iterations: 20) do
        BenchmarkHelper.client.execute("SELECT * FROM #{BENCHMARK_TABLE} LIMIT 1000")
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 4: SELECT with large result set (10000 rows)
      puts "\n--- Benchmark 4: SELECT 10000 Rows ---"
      result = BenchmarkHelper.measure_latency("SELECT 10000 rows", iterations: 10) do
        BenchmarkHelper.client.execute("SELECT * FROM #{BENCHMARK_TABLE} LIMIT 10000")
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 5: Aggregation query
      puts "\n--- Benchmark 5: Aggregation Query ---"
      result = BenchmarkHelper.measure_latency("COUNT(*) aggregation", iterations: 50) do
        BenchmarkHelper.client.execute("SELECT count() FROM #{BENCHMARK_TABLE}")
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 6: Complex aggregation
      puts "\n--- Benchmark 6: Complex Aggregation ---"
      result = BenchmarkHelper.measure_latency("GROUP BY aggregation", iterations: 30) do
        BenchmarkHelper.client.execute(<<~SQL)
          SELECT
            toStartOfHour(created_at) AS hour,
            count() AS cnt,
            avg(value) AS avg_value
          FROM #{BENCHMARK_TABLE}
          GROUP BY hour
          ORDER BY hour
          LIMIT 24
        SQL
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 7: Format comparison (JSONCompact vs JSON)
      puts "\n--- Benchmark 7: Format Comparison ---"
      BenchmarkHelper.compare_benchmarks(warmup: 1, time: 3) do |x|
        x.report("JSONCompact (default)") do
          BenchmarkHelper.client.execute("SELECT * FROM #{BENCHMARK_TABLE} LIMIT 100", format: "JSONCompact")
        end

        x.report("JSON format") do
          BenchmarkHelper.client.execute("SELECT * FROM #{BENCHMARK_TABLE} LIMIT 100", format: "JSON")
        end
      end

      # Benchmark 8: Throughput test
      puts "\n--- Benchmark 8: Query Throughput ---"
      throughput = BenchmarkHelper.measure_throughput("Simple SELECT throughput", duration_seconds: 5) do
        BenchmarkHelper.client.execute("SELECT 1")
      end
      results << throughput
      BenchmarkHelper.print_result(throughput)

      # Benchmark 9: Result iteration performance
      puts "\n--- Benchmark 9: Result Iteration ---"
      BenchmarkHelper.compare_benchmarks(warmup: 1, time: 3) do |x|
        x.report("each row (1000 rows)") do
          result = BenchmarkHelper.client.execute("SELECT * FROM #{BENCHMARK_TABLE} LIMIT 1000")
          result.each { |row| row["id"] }
        end

        x.report("to_a (1000 rows)") do
          result = BenchmarkHelper.client.execute("SELECT * FROM #{BENCHMARK_TABLE} LIMIT 1000")
          result.to_a
        end

        x.report("first only (1000 rows)") do
          result = BenchmarkHelper.client.execute("SELECT * FROM #{BENCHMARK_TABLE} LIMIT 1000")
          result.first
        end
      end

      BenchmarkHelper.print_summary(results)
    ensure
      cleanup_test_data
    end

    private

    def setup_test_data
      puts "\nSetting up benchmark test data..."

      BenchmarkHelper.create_benchmark_table(BENCHMARK_TABLE, columns: {
        "id" => "UInt64",
        "name" => "String",
        "value" => "Float64",
        "category" => "String",
        "created_at" => "DateTime",
      },)

      # Insert 50,000 rows for query benchmarks
      batch_size = 10_000
      total_rows = 50_000

      (0...total_rows).step(batch_size) do |offset|
        rows = (1..batch_size).map do |i|
          {
            id: offset + i,
            name: "item_#{offset + i}",
            value: (offset + i) * 1.5,
            category: "category_#{(offset + i) % 10}",
            created_at: Time.now - (offset + i),
          }
        end
        BenchmarkHelper.client.insert(BENCHMARK_TABLE, rows)
        print "."
      end

      puts " Done! Inserted #{total_rows} rows."
    end

    def cleanup_test_data
      puts "\nCleaning up benchmark test data..."
      BenchmarkHelper.drop_benchmark_table(BENCHMARK_TABLE)
      puts "Done!"
    end
  end
end

# Run the benchmark if this file is executed directly
QueryBenchmark.run if __FILE__ == $PROGRAM_NAME
