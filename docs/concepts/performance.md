# Performance Tuning Guide

This guide covers performance optimization techniques, benchmarking, and performance analysis for ClickhouseRuby applications.

## Table of Contents

1. [Performance Benchmarking](#performance-benchmarking)
2. [Query Optimization](#query-optimization)
3. [Connection Pool Tuning](#connection-pool-tuning)
4. [Compression Configuration](#compression-configuration)
5. [Retry Strategy Tuning](#retry-strategy-tuning)

---

## Performance Benchmarking

ClickhouseRuby includes a comprehensive benchmark suite for measuring performance and verifying that the client meets performance targets. Use benchmarks to:

- Verify performance targets are met
- Compare performance across versions
- Identify performance regressions
- Tune configuration for your workload

### Running Benchmarks

```bash
# Run all benchmarks (requires ClickHouse running)
rake benchmark

# Run quick benchmark (subset of all benchmarks)
rake benchmark:quick

# Run specific benchmark suites
rake benchmark:connection  # Connection establishment benchmarks
rake benchmark:query      # Query execution benchmarks
rake benchmark:insert     # Insert performance benchmarks
```

### Benchmark Tasks

**Full Benchmark Suite (`rake benchmark`):**
- Connection establishment latency
- Simple SELECT query overhead
- Bulk insert throughput (various batch sizes)
- Streaming performance
- Pool checkout/checkin overhead

**Quick Benchmark (`rake benchmark:quick`):**
- Connection establishment (10 iterations)
- Simple SELECT (50 iterations)
- Bulk insert 1K rows (10 iterations)

**Connection Benchmarks (`rake benchmark:connection`):**
- Connection establishment time
- Ping latency
- Pool checkout/checkin overhead

**Query Benchmarks (`rake benchmark:query`):**
- Simple SELECT overhead
- Complex query performance
- Streaming query performance
- Result deserialization cost

**Insert Benchmarks (`rake benchmark:insert`):**
- Single row insert
- Batch insert (1K, 10K, 100K rows)
- Bulk insert throughput
- JSONEachRow format performance

### Performance Targets

From MVP requirements, ClickhouseRuby targets:

- **Connection establishment**: < 100ms
- **Simple SELECT overhead**: < 50ms
- **Bulk INSERT (10K rows)**: < 1 second

Benchmarks report whether these targets are met and provide detailed statistics:

```
Connection Establishment
  Target: < 100ms
  Result: 45.2ms (PASS)
  Min: 32.1ms, Max: 78.5ms, Avg: 45.2ms, Median: 43.8ms
  P95: 67.3ms, P99: 75.2ms
```

### Interpreting Results

Benchmark output includes:

- **Latency statistics**: min, max, avg, median, P95, P99
- **Throughput**: operations per second, rows per second
- **Target comparison**: PASS/FAIL against performance targets
- **Iterations**: number of test iterations run

**Example Output:**

```
=== Connection Benchmark ===
Connect + Ping (10 iterations)
  Target: < 100ms
  Result: 45.2ms (PASS)
  Min: 32.1ms, Max: 78.5ms, Avg: 45.2ms, Median: 43.8ms
  P95: 67.3ms, P99: 75.2ms

=== Query Benchmark ===
SELECT 1 (50 iterations)
  Target: < 50ms
  Result: 12.5ms (PASS)
  Min: 8.2ms, Max: 25.3ms, Avg: 12.5ms, Median: 11.8ms
  P95: 20.1ms, P99: 23.5ms

=== Insert Benchmark ===
Insert 1K rows (10 iterations)
  Target: < 1s
  Result: 234.5ms (PASS)
  Min: 198.2ms, Max: 312.4ms, Avg: 234.5ms, Median: 228.1ms
  P95: 298.7ms, P99: 308.2ms
```

### Custom Benchmarks

Create custom benchmarks using the benchmark helper:

```ruby
require_relative 'benchmark/benchmark_helper'

# Ensure ClickHouse is available
BenchmarkHelper.ensure_clickhouse_available!

# Measure custom operation
result = BenchmarkHelper.measure_latency("Custom Operation", iterations: 100) do
  client.execute('SELECT count() FROM events')
end

BenchmarkHelper.print_result(result, target_key: :custom_operation_ms)
```

### Benchmark Environment

Benchmarks require:

- ClickHouse server running (local or remote)
- `CLICKHOUSE_HOST` and `CLICKHOUSE_PORT` environment variables (optional, defaults to localhost:8123)
- `benchmark-ips` gem (development dependency)

```bash
# Start ClickHouse
docker-compose up -d

# Set environment variables (optional)
export CLICKHOUSE_HOST=localhost
export CLICKHOUSE_PORT=8123

# Run benchmarks
rake benchmark
```

### Continuous Benchmarking

Integrate benchmarks into CI/CD to catch performance regressions:

```yaml
# .github/workflows/benchmark.yml
name: Performance Benchmarks

on:
  pull_request:
    paths:
      - 'lib/**'
      - 'benchmark/**'

jobs:
  benchmark:
    runs-on: ubuntu-latest
    services:
      clickhouse:
        image: clickhouse/clickhouse-server
        ports:
          - 8123:8123
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
      - run: bundle install
      - run: rake benchmark:quick
```

### Best Practices

1. **Run benchmarks on consistent hardware** - Network latency and CPU affect results
2. **Warm up before benchmarking** - First connection/query may be slower
3. **Run multiple iterations** - Single measurements can be misleading
4. **Compare against targets** - Use MVP targets as baseline
5. **Monitor trends** - Track performance over time to catch regressions

---

## Query Optimization

### Use EXPLAIN to Analyze Queries

Use EXPLAIN to understand query execution and optimize performance:

```ruby
# Explain execution plan
plan = client.explain('SELECT * FROM events WHERE date = today()')
# Review: Are indexes being used? Are filters applied early?

# Explain pipeline
pipeline = client.explain('SELECT * FROM events', type: :pipeline)
# Review: Are there bottlenecks? Can stages be parallelized?

# Estimate cost before running expensive queries
estimate = client.explain('SELECT count() FROM huge_table', type: :estimate)
# Review: How many rows/bytes will be read?
```

See [Usage Guide - Query Analysis](USAGE.md#query-analysis) for complete EXPLAIN documentation.

### Use PREWHERE for Early Filtering

PREWHERE filters rows before reading all columns, reducing I/O:

```ruby
# With PREWHERE - reads fewer columns
Event.prewhere(date: Date.today).where(status: 'active')
# SELECT * FROM events PREWHERE date = '2024-02-02' WHERE status = 'active'

# Without PREWHERE - reads all columns first
Event.where(date: Date.today, status: 'active')
# SELECT * FROM events WHERE date = '2024-02-02' AND status = 'active'
```

See [PREWHERE Feature Guide](features/prewhere.md) for details.

### Use SAMPLE for Approximate Queries

When exact counts aren't needed, use SAMPLE for faster results:

```ruby
# Approximate count (10% sample)
Event.sample(0.1).count
# SELECT count() FROM events SAMPLE 0.1

# Much faster than exact count on large tables
Event.count  # Slow on billions of rows
```

See [SAMPLE Feature Guide](features/sample.md) for details.

### Optimize INSERT Performance

Use batch inserts and JSONEachRow format:

```ruby
# GOOD: Batch insert (uses JSONEachRow automatically)
client.insert('events', large_array_of_hashes)
# ~5x faster than VALUES format

# BAD: Single row inserts
large_array.each { |row| client.insert('events', [row]) }
```

---

## Connection Pool Tuning

### Determine Optimal Pool Size

Pool size should match your concurrency patterns:

```ruby
# Low concurrency (1-5 concurrent requests)
config.pool_size = 5

# Medium concurrency (5-15 concurrent requests)
config.pool_size = 10

# High concurrency (15+ concurrent requests)
config.pool_size = 20

# Very high concurrency (multiple processes/threads)
config.pool_size = 50
```

### Monitor Pool Utilization

Track pool metrics to identify bottlenecks:

```ruby
stats = client.pool_stats

# If available is consistently 0, increase pool_size
if stats[:available] == 0
  logger.warn("Pool exhausted, consider increasing pool_size")
end

# If in_use is consistently low, you can reduce pool_size
if stats[:in_use] < stats[:size] * 0.3
  logger.info("Pool underutilized, consider reducing pool_size")
end
```

### Reduce Query Time

Faster queries free connections faster:

```ruby
# Add indexes
client.command('ALTER TABLE events ADD INDEX idx_date date TYPE minmax GRANULARITY 1')

# Use PREWHERE for early filtering
Event.prewhere(date: Date.today)

# Limit result sets
Event.limit(1000)

# Use SAMPLE for approximate queries
Event.sample(0.1).count
```

---

## Compression Configuration

### When to Enable Compression

Enable compression for:
- Large payloads (>1KB)
- Low-bandwidth networks
- High-volume applications

```ruby
# Enable compression
config.compression = 'gzip'
config.compression_threshold = 1024  # Minimum 1KB

# High-throughput, large batches
config.compression_threshold = 10_000  # Only compress large payloads

# Low-bandwidth environments
config.compression_threshold = 100  # Compress even small responses

# CPU-limited environments
config.compression = nil  # Disable compression
```

### Compression Trade-offs

- **Benefit**: Reduces network bandwidth by 3-10x
- **Cost**: CPU used for compression/decompression
- **Best for**: Large result sets, bulk inserts

See [HTTP Compression Feature Guide](features/http_compression.md) for details.

---

## Retry Strategy Tuning

### Default Retry Configuration

```ruby
config.max_retries = 3
config.initial_backoff = 1.0        # Start with 1 second
config.backoff_multiplier = 1.6     # Exponential backoff
config.max_backoff = 120.0          # Cap at 2 minutes
config.retry_jitter = :equal        # Add jitter to prevent thundering herd
```

### Conservative Retry (Low Latency)

For low-latency requirements:

```ruby
config.max_retries = 1              # Only 1 retry
config.initial_backoff = 0.1        # Start immediately
```

### Aggressive Retry (High Reliability)

For high-reliability requirements:

```ruby
config.max_retries = 5              # Many retries
config.initial_backoff = 2.0        # Wait longer between attempts
config.max_backoff = 60.0           # Cap shorter
```

### Retry Jitter Strategies

```ruby
# :full - Random between 0 and calculated delay (high variance)
config.retry_jitter = :full

# :equal - Half fixed + half random (default, balanced)
config.retry_jitter = :equal

# :none - Pure exponential backoff without randomization
config.retry_jitter = :none
```

See [Retry Logic Feature Guide](features/retry_logic.md) for details.

---

## Performance Tips Summary

1. **Use batch inserts** - Insert multiple rows at once
2. **Use streaming** - For queries returning millions of rows
3. **Enable compression** - For large payloads (>1KB)
4. **Configure retries** - For transient failures
5. **Tune pool size** - Based on concurrent request patterns
6. **Use PREWHERE** - For query optimization (ActiveRecord only)
7. **Use SAMPLE** - For approximate queries when exact counts aren't needed
8. **Use EXPLAIN** - To analyze and optimize query execution
9. **Monitor metrics** - Track pool utilization and query performance
10. **Benchmark regularly** - Catch performance regressions early

---

## See Also

- **[Usage Guide](USAGE.md)** - Common operations and query examples
- **[Production Guide](PRODUCTION_GUIDE.md)** - Production deployment considerations
- **[Advanced Features](ADVANCED_FEATURES.md)** - Advanced usage patterns
- **[Feature Guides](features/)** - Detailed feature documentation
