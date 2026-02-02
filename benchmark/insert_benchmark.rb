#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark for ClickhouseRuby insert performance
#
# This benchmark measures:
# - Bulk INSERT performance (target: 10K rows < 1 second)
# - Different batch sizes
# - Insert throughput
# - Memory efficiency for large inserts
#
# Usage:
#   ruby benchmark/insert_benchmark.rb
#   CLICKHOUSE_HOST=my-host ruby benchmark/insert_benchmark.rb

require_relative "benchmark_helper"

module InsertBenchmark
  BENCHMARK_TABLE = "benchmark_insert_test"

  class << self
    def run
      BenchmarkHelper.print_header("Insert Performance")
      BenchmarkHelper.ensure_clickhouse_available!

      results = []

      # Benchmark 1: Single row insert
      puts "\n--- Benchmark 1: Single Row Insert ---"
      setup_insert_table
      result = BenchmarkHelper.measure_latency("Single row insert", iterations: 100) do
        row = generate_single_row
        BenchmarkHelper.client.insert(BENCHMARK_TABLE, [row])
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 2: Small batch insert (100 rows)
      puts "\n--- Benchmark 2: Small Batch Insert (100 rows) ---"
      setup_insert_table
      result = BenchmarkHelper.measure_latency("100 row batch insert", iterations: 50) do
        rows = generate_rows(100)
        BenchmarkHelper.client.insert(BENCHMARK_TABLE, rows)
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 3: Medium batch insert (1000 rows)
      puts "\n--- Benchmark 3: Medium Batch Insert (1000 rows) ---"
      setup_insert_table
      result = BenchmarkHelper.measure_latency("1000 row batch insert", iterations: 20) do
        rows = generate_rows(1000)
        BenchmarkHelper.client.insert(BENCHMARK_TABLE, rows)
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 4: Large batch insert (10K rows) - MVP Target
      puts "\n--- Benchmark 4: Large Batch Insert (10K rows) - MVP Target ---"
      setup_insert_table
      result = BenchmarkHelper.measure_latency("10K row batch insert", iterations: 10) do
        rows = generate_rows(10_000)
        BenchmarkHelper.client.insert(BENCHMARK_TABLE, rows)
      end
      # Convert avg_ms to seconds for the 1-second target
      result[:target_key] = :bulk_insert_10k_seconds
      result[:duration_seconds] = result[:avg_ms] / 1000.0
      results << result
      BenchmarkHelper.print_result(result)
      target_met = result[:avg_ms] <= 1000
      puts "  Target: 1000 ms [#{target_met ? "PASS" : "FAIL"}]"

      # Benchmark 5: Very large batch insert (50K rows)
      puts "\n--- Benchmark 5: Very Large Batch Insert (50K rows) ---"
      setup_insert_table
      result = BenchmarkHelper.measure_latency("50K row batch insert", iterations: 5) do
        rows = generate_rows(50_000)
        BenchmarkHelper.client.insert(BENCHMARK_TABLE, rows)
      end
      results << result
      BenchmarkHelper.print_result(result)

      # Benchmark 6: Batch size comparison
      puts "\n--- Benchmark 6: Batch Size Comparison (same total: 10K rows) ---"
      BenchmarkHelper.compare_benchmarks(warmup: 1, time: 5) do |x|
        x.report("100 batches x 100 rows") do
          setup_insert_table
          100.times do
            rows = generate_rows(100)
            BenchmarkHelper.client.insert(BENCHMARK_TABLE, rows)
          end
        end

        x.report("10 batches x 1000 rows") do
          setup_insert_table
          10.times do
            rows = generate_rows(1000)
            BenchmarkHelper.client.insert(BENCHMARK_TABLE, rows)
          end
        end

        x.report("1 batch x 10000 rows") do
          setup_insert_table
          rows = generate_rows(10_000)
          BenchmarkHelper.client.insert(BENCHMARK_TABLE, rows)
        end
      end

      # Benchmark 7: Insert throughput (rows per second)
      puts "\n--- Benchmark 7: Insert Throughput ---"
      setup_insert_table
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      total_rows = 0
      duration = 10 # seconds

      while Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time < duration
        rows = generate_rows(1000)
        BenchmarkHelper.client.insert(BENCHMARK_TABLE, rows)
        total_rows += 1000
        print "."
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      rows_per_second = total_rows / elapsed

      throughput_result = {
        label: "Insert throughput",
        total_rows: total_rows,
        duration_seconds: elapsed.round(2),
        rows_per_second: rows_per_second.round(0),
      }
      results << throughput_result

      puts "\n  Total rows: #{total_rows}"
      puts "  Duration: #{elapsed.round(2)} seconds"
      puts "  Throughput: #{rows_per_second.round(0)} rows/second"

      # Benchmark 8: Different column types
      puts "\n--- Benchmark 8: Column Type Complexity ---"
      BenchmarkHelper.compare_benchmarks(warmup: 1, time: 3) do |x|
        x.report("Simple columns (3 cols)") do
          setup_simple_table
          rows = (1..1000).map do |i|
            { id: i, name: "test_#{i}", value: i * 1.5 }
          end
          BenchmarkHelper.client.insert("benchmark_simple_test", rows)
        end

        x.report("Complex columns (with arrays/maps)") do
          setup_complex_table
          rows = (1..1000).map do |i|
            {
              id: i,
              name: "test_#{i}",
              tags: %w[tag1 tag2 tag3],
              metadata: { "key1" => "value1", "key2" => "value2" },
              created_at: Time.now,
            }
          end
          BenchmarkHelper.client.insert("benchmark_complex_test", rows)
        end
      end

      # Print summary
      BenchmarkHelper.print_summary(results.select { |r| r[:target_key] })

      # Additional metrics
      puts "\n#{"=" * 60}"
      puts "ADDITIONAL METRICS"
      puts "=" * 60
      puts "  Peak insert throughput: #{rows_per_second.round(0)} rows/second"
      puts "  Recommended batch size: 1000-10000 rows"
      puts "=" * 60
    ensure
      cleanup_tables
    end

    private

    def setup_insert_table
      BenchmarkHelper.create_benchmark_table(BENCHMARK_TABLE, columns: {
        "id" => "UInt64",
        "name" => "String",
        "value" => "Float64",
        "category" => "String",
        "created_at" => "DateTime",
      },)
    end

    def setup_simple_table
      BenchmarkHelper.client.command("DROP TABLE IF EXISTS benchmark_simple_test")
      BenchmarkHelper.client.command(<<~SQL)
        CREATE TABLE benchmark_simple_test (
          id UInt64,
          name String,
          value Float64
        ) ENGINE = MergeTree()
        ORDER BY id
      SQL
    end

    def setup_complex_table
      BenchmarkHelper.client.command("DROP TABLE IF EXISTS benchmark_complex_test")
      BenchmarkHelper.client.command(<<~SQL)
        CREATE TABLE benchmark_complex_test (
          id UInt64,
          name String,
          tags Array(String),
          metadata Map(String, String),
          created_at DateTime
        ) ENGINE = MergeTree()
        ORDER BY id
      SQL
    end

    def generate_single_row
      now = Time.now
      {
        id: rand(1_000_000_000),
        name: "item_#{rand(1000)}",
        value: rand * 100,
        category: "category_#{rand(10)}",
        created_at: now,
      }
    end

    def generate_rows(count)
      now = Time.now
      (1..count).map do |i|
        {
          id: i + rand(1_000_000_000),
          name: "item_#{i}",
          value: i * 1.5,
          category: "category_#{i % 10}",
          created_at: now,
        }
      end
    end

    def cleanup_tables
      puts "\nCleaning up benchmark tables..."
      BenchmarkHelper.drop_benchmark_table(BENCHMARK_TABLE)
      BenchmarkHelper.client.command("DROP TABLE IF EXISTS benchmark_simple_test")
      BenchmarkHelper.client.command("DROP TABLE IF EXISTS benchmark_complex_test")
      puts "Done!"
    end
  end
end

# Run the benchmark if this file is executed directly
InsertBenchmark.run if __FILE__ == $PROGRAM_NAME
