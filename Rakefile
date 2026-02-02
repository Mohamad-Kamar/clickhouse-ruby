# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = ["--format", "documentation"]
end

RSpec::Core::RakeTask.new(:spec_unit) do |t|
  t.rspec_opts = ["--format", "documentation", "--tag", "~integration"]
end

RSpec::Core::RakeTask.new(:spec_integration) do |t|
  t.rspec_opts = ["--format", "documentation", "--tag", "integration"]
end

RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = ["--display-cop-names"]
end

RuboCop::RakeTask.new(:rubocop_fix) do |t|
  t.options = ["--autocorrect-all", "--display-cop-names"]
end

desc "Generate YARD documentation"
task :yard do
  require "yard"
  YARD::Rake::YardocTask.new do |t|
    t.files = ["lib/**/*.rb"]
    t.options = ["--output-dir", "doc", "--markup", "markdown"]
  end
end

desc "Run all checks (specs and rubocop)"
task check: %i[spec rubocop]

# Benchmark tasks
namespace :benchmark do
  desc "Run all benchmarks (requires ClickHouse)"
  task :all do
    Rake::Task["benchmark:connection"].invoke
    Rake::Task["benchmark:query"].invoke
    Rake::Task["benchmark:insert"].invoke
  end

  desc "Run connection benchmarks"
  task :connection do
    ruby "benchmark/connection_benchmark.rb"
  end

  desc "Run query benchmarks"
  task :query do
    ruby "benchmark/query_benchmark.rb"
  end

  desc "Run insert benchmarks"
  task :insert do
    ruby "benchmark/insert_benchmark.rb"
  end

  desc "Quick benchmark (subset of all benchmarks)"
  task :quick do
    require_relative "benchmark/benchmark_helper"

    puts "=" * 60
    puts "Quick Benchmark"
    puts "=" * 60

    BenchmarkHelper.ensure_clickhouse_available!

    # Connection establishment
    puts "\n--- Connection Establishment ---"
    result = BenchmarkHelper.measure_latency("Connect + Ping", iterations: 10) do
      config = {
        host: ENV.fetch("CLICKHOUSE_HOST", "localhost"),
        port: ENV.fetch("CLICKHOUSE_PORT", 8123).to_i,
        database: "default",
        use_ssl: false,
        connect_timeout: 5,
      }
      conn = ClickhouseRuby::Connection.new(**config)
      conn.connect
      conn.ping
      conn.disconnect
    end
    BenchmarkHelper.print_result(result, target_key: :connection_establishment_ms)

    # Simple SELECT
    puts "\n--- Simple SELECT ---"
    result = BenchmarkHelper.measure_latency("SELECT 1", iterations: 50) do
      BenchmarkHelper.client.execute("SELECT 1")
    end
    BenchmarkHelper.print_result(result, target_key: :simple_select_overhead_ms)

    # Bulk insert (1K rows for quick test)
    puts "\n--- Bulk Insert (1K rows) ---"
    BenchmarkHelper.client.command("DROP TABLE IF EXISTS benchmark_quick_test")
    BenchmarkHelper.client.command(<<~SQL)
      CREATE TABLE benchmark_quick_test (
        id UInt64,
        name String,
        value Float64
      ) ENGINE = MergeTree()
      ORDER BY id
    SQL

    result = BenchmarkHelper.measure_latency("Insert 1K rows", iterations: 10) do
      rows = (1..1000).map { |i| { id: i, name: "item_#{i}", value: i * 1.5 } }
      BenchmarkHelper.client.insert("benchmark_quick_test", rows)
    end
    BenchmarkHelper.print_result(result)

    # Cleanup
    BenchmarkHelper.client.command("DROP TABLE IF EXISTS benchmark_quick_test")

    puts "\n#{"=" * 60}"
    puts "Quick benchmark complete!"
    puts "=" * 60
  end
end

desc "Run benchmarks (alias for benchmark:all)"
task benchmark: "benchmark:all"

task default: :spec
