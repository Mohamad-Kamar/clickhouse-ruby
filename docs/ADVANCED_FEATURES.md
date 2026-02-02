# Advanced ClickhouseRuby Features

This guide covers advanced usage patterns, optimization techniques, and internals of
ClickhouseRuby beyond the basics covered in the README. It's designed for production
deployments, high-throughput applications, and developers integrating deeply with the
library.

Each section includes practical examples, performance considerations, and common gotchas
you should be aware of when using these features in production.

## Table of Contents

1. [Pool Management](#1-pool-management)
2. [Module-Level API](#2-module-level-api)
3. [Result Utilities](#3-result-utilities)
4. [Streaming Enhancements](#4-streaming-enhancements)
5. [Configuration Helpers](#5-configuration-helpers)
6. [Enhanced Error Information](#6-enhanced-error-information)
7. [Type System Internals](#7-type-system-internals)

---

## 1. Pool Management

The connection pool is the foundation of ClickhouseRuby's performance. Understanding
pool lifecycle, monitoring, and tuning is critical for production applications.

### Connection Pool Lifecycle

Each Client maintains its own ConnectionPool instance. The pool manages a fixed-size
set of HTTP connections (default: 5 connections) to the ClickHouse server.

```ruby
config = ClickhouseRuby::Configuration.new
config.host = 'clickhouse.example.com'
config.pool_size = 10      # Number of connections to maintain
config.pool_timeout = 5    # Seconds to wait for a connection

client = ClickhouseRuby::Client.new(config)

# Connections are checked out for each query
result = client.execute('SELECT 1')  # Checkout, query, checkin
result = client.execute('SELECT 2')  # Reuse same connection
```

The pool automatically creates connections on-demand up to `pool_size`. When all
connections are in-use, subsequent queries block until a connection becomes available
or `pool_timeout` seconds elapse.

### Health Checks and Monitoring

Monitor pool health using `pool_stats` and `health_check`:

```ruby
# Get current pool statistics
stats = client.pool_stats
# => {
#   size: 5,           # Total pool capacity
#   available: 3,      # Currently idle connections
#   in_use: 2,         # Currently active connections
#   total_created: 12, # Lifetime connections created
#   failed_checks: 1   # Lifetime failed health checks
# }

# Verify all connections are healthy
client.pool.health_check
# Returns nil if healthy, raises exception if check fails
```

Use `pool_stats` in health check endpoints and dashboards:

```ruby
# In a Rails health check endpoint
get '/health/pool' do
  stats = client.pool_stats
  if stats[:available] > 0
    json({ status: 'ok', pool: stats })
  else
    json({ status: 'warning', pool: stats }, status: 503)
  end
end
```

### Idle Connection Cleanup

Long-running applications should periodically clean up idle connections to reclaim
system resources and refresh connections that may have gone stale:

```ruby
# Remove idle connections older than 5 minutes
client.pool.cleanup(max_idle_seconds: 300)

# Run cleanup every 10 minutes in a background job
class PoolCleanupJob
  include Sidekiq::Job

  sidekiq_options retry: 0

  def perform
    client = ClickhouseRuby.client
    removed_count = client.pool.cleanup(max_idle_seconds: 300)
    logger.info("Pool cleanup: removed #{removed_count} idle connections")
  rescue => e
    logger.error("Pool cleanup failed: #{e.message}")
  end
end
```

### Thread-Safety Guarantees

The connection pool is thread-safe and designed for concurrent access. Each thread
gets its own connection from the pool:

```ruby
# Thread-safe usage in a Rails controller
class EventsController < ApplicationController
  def track
    client = ClickhouseRuby.client
    # Each request thread gets its own connection from the pool
    client.insert('events', event_params)
    render json: { status: 'ok' }
  end
end

# Thread-safe usage in Sidekiq workers
class EventProcessor
  include Sidekiq::Worker

  def perform(event_id)
    client = ClickhouseRuby.client
    event = Event.find(event_id)
    # Worker thread gets a connection from the shared pool
    client.insert('processed_events', format_event(event))
  end
end
```

All pool operations use Mutex synchronization internally. The `with_connection` method
provides explicit control:

```ruby
# Manual connection management with explicit block
client.pool.with_connection do |conn|
  response = conn.execute('SELECT 1')
  puts response.body
end
# Connection automatically checked back in
```

### Pool Exhaustion and Tuning

Pool exhaustion occurs when all connections are in-use and a new query arrives.
Symptoms include:

- Timeout exceptions: `Timeout::Error` or `ClickhouseRuby::PoolError`
- Increased P99 latency
- Queue buildup in logs

Tuning strategies:

```ruby
# Strategy 1: Increase pool size for high concurrency
config.pool_size = 20        # For 16+ concurrent requests

# Strategy 2: Reduce query time to free connections faster
# - Add indexes, optimize queries, use PREWHERE
# - Lower max_execution_time in settings if queries stall

# Strategy 3: Reduce pool_timeout to fail fast
config.pool_timeout = 1      # Fail quickly instead of blocking

# Strategy 4: Use multiple clients for read/write separation
read_client = ClickhouseRuby::Client.new(read_config)
write_client = ClickhouseRuby::Client.new(write_config)
```

### Common Gotchas

**Gotcha 1: Pool Leaks from Exceptions**

If an exception occurs during query execution, ensure the connection is returned:

```ruby
# BAD: Connection may not be returned if exception occurs
result = client.with_connection { |conn| conn.execute('...') }

# GOOD: Automatic cleanup with public API
result = client.execute('...')

# GOOD: Explicit try-finally if needed
begin
  result = client.with_connection { |conn| conn.execute('...') }
rescue => e
  # Connection is returned even if exception occurs
  raise
end
```

**Gotcha 2: Per-Process vs Shared Pool**

Each Client instance has its own pool. In a Rails app with N processes, you have N
pools. This is intentional but affects resource usage:

```ruby
# Each process has separate pool (N × pool_size connections total)
# In a 4-process server with pool_size=5: 20 total connections
ClickhouseRuby.configure { |c| c.pool_size = 5 }

# Solution: Use single shared client per process
ClickhouseRuby.configure do |config|
  config.host = 'clickhouse.example.com'
  config.pool_size = 10  # Per-process, so 40 total in 4-process server
end

in_initializer :clickhouse do
  ClickhouseRuby.ensure_client # Create shared instance
end
```

**Gotcha 3: Blocking on Connection Checkout**

Long `pool_timeout` values can degrade response times under load:

```ruby
# BAD: Block for 30 seconds if pool exhausted (very bad UX)
config.pool_timeout = 30

# GOOD: Fail fast and respond quickly
config.pool_timeout = 2    # Rails default is 5 seconds
config.pool_size = 20      # Increase capacity instead
```

---

## 2. Module-Level API

ClickhouseRuby provides both instance-based and module-level APIs. The module-level
API simplifies single-client scenarios and Rails integration.

### Global Configuration

Configure ClickhouseRuby globally to use a shared default client:

```ruby
# In config/initializers/clickhouse.rb
ClickhouseRuby.configure do |config|
  config.host = ENV['CLICKHOUSE_HOST'] || 'localhost'
  config.port = ENV['CLICKHOUSE_PORT'].to_i || 8123
  config.database = ENV['CLICKHOUSE_DATABASE'] || 'default'
  config.username = ENV['CLICKHOUSE_USERNAME']
  config.password = ENV['CLICKHOUSE_PASSWORD']
  config.ssl = ENV['CLICKHOUSE_SSL'] != 'false'
  config.pool_size = 10
  config.max_retries = 3
  config.logger = Rails.logger
end

# Use module-level API directly
ClickhouseRuby.execute('SELECT count() FROM users')
ClickhouseRuby.insert('events', [{ id: 1, name: 'test' }])
ClickhouseRuby.ping
```

### Module-Level Methods

After configuring ClickhouseRuby, use convenience methods:

```ruby
# Execute queries (returns Result)
result = ClickhouseRuby.execute('SELECT * FROM users LIMIT 10')
result.each { |row| puts row }

# Execute commands (no return value)
ClickhouseRuby.command('DROP TABLE IF EXISTS users')

# Insert data (bulk operation)
ClickhouseRuby.insert('events', [
  { id: 1, event: 'click', timestamp: Time.now },
  { id: 2, event: 'view', timestamp: Time.now },
])

# Stream results (memory efficient)
ClickhouseRuby.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
end

# Health check
ClickhouseRuby.ping

# Get underlying client
client = ClickhouseRuby.client
```

### Per-Query Settings

Pass settings to individual queries:

```ruby
# Query-specific settings
result = ClickhouseRuby.execute(
  'SELECT * FROM large_table',
  settings: { max_execution_time: 120, max_threads: 4 }
)

# Combine with global defaults (per-query settings override)
# Global default_settings apply automatically
# Then query-specific settings override global settings
```

### Multi-Database Scenarios

For applications accessing multiple ClickHouse instances:

```ruby
# Create separate clients for different databases
analytics_config = ClickhouseRuby::Configuration.new
analytics_config.host = 'analytics.internal'
analytics_config.database = 'metrics'
analytics_client = ClickhouseRuby::Client.new(analytics_config)

transactional_config = ClickhouseRuby::Configuration.new
transactional_config.host = 'transactional.internal'
transactional_config.database = 'operational'
transactional_client = ClickhouseRuby::Client.new(transactional_config)

# Use appropriately
analytics_result = analytics_client.execute('SELECT ...')
events = transactional_client.execute('SELECT ...')

# Or use pattern with class variables
class ClickhouseService
  class << self
    def analytics
      @analytics_client ||= ClickhouseRuby::Client.new(...)
    end

    def transactional
      @transactional_client ||= ClickhouseRuby::Client.new(...)
    end
  end
end

# Usage
ClickhouseService.analytics.execute('SELECT ...')
ClickhouseService.transactional.insert('events', data)
```

### Thread Safety

The module-level client is thread-safe. Each thread gets a connection from the shared
pool:

```ruby
# Safe in multi-threaded environment
Thread.new do
  result = ClickhouseRuby.execute('SELECT 1')
  puts result.first
end

Thread.new do
  ClickhouseRuby.insert('events', data)
end
```

### When to Use Module-Level vs Instance-Based

Use **module-level API** when:
- Single ClickHouse instance in your application
- Simple, straightforward usage patterns
- Rails application with centralized configuration

Use **instance-based API** when:
- Multiple ClickHouse instances (analytics, operational, etc.)
- Need distinct configurations per instance
- Building a library or framework that should be agnostic to configuration

```ruby
# Module-level: Simple Rails app
ClickhouseRuby.execute('SELECT ...')

# Instance-based: Complex multi-database system
class AnalyticsQueryService
  def initialize
    @client = ClickhouseRuby::Client.new(analytics_config)
  end

  def report_data
    @client.execute('SELECT ...')
  end
end
```

---

## 3. Result Utilities

Query results are wrapped in a `Result` object providing rich metadata and convenient
access patterns.

### Column Introspection

Inspect result structure before processing data:

```ruby
result = client.execute('SELECT id, name, age FROM users LIMIT 10')

# Get column names
columns = result.columns
# => ['id', 'name', 'age']

# Get column types
types = result.types
# => [ClickhouseRuby::Types::Integer, ClickhouseRuby::Types::String,
#     ClickhouseRuby::Types::Integer]

# Get column type objects (deserialized from ClickHouse type strings)
column_types = result.column_types
# => { 'id' => Integer type object, 'name' => String type object, ... }

# Dynamic processing based on types
result.columns.each_with_index do |col, idx|
  type = result.types[idx]
  puts "Column #{col}: #{type.class.name}"
end
```

### Data Access Patterns

Access result data in multiple ways:

```ruby
result = client.execute('SELECT id, name FROM users')

# Iterator pattern (recommended for large results)
result.each { |row| puts row['name'] }

# Array-like access
first_row = result.first
# => { 'id' => 1, 'name' => 'Alice' }

last_row = result.last
# => { 'id' => 100, 'name' => 'Zoe' }

row_5 = result[5]

# Conversion to array
rows = result.to_a
# => [{ 'id' => 1, ... }, { 'id' => 2, ... }, ...]

# Count rows
count = result.count
```

### Column Value Extraction

Extract specific columns efficiently:

```ruby
result = client.execute('SELECT id, name, email FROM users')

# Get all values for a column
user_ids = result.column_values('id')
# => [1, 2, 3, 4, 5]

user_names = result.column_values('name')
# => ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve']

# Use case: Bulk operations based on extracted values
user_ids = result.column_values('id')
user_ids.each { |id| process_user(id) }

# Use case: Dynamic field extraction
fields = %w[id name email]
field_values = fields.map { |field| result.column_values(field) }
# => [[1, 2, 3], ['Alice', 'Bob', 'Charlie'], ['a@x.com', 'b@x.com', ...]]
```

### Metadata and Statistics

ClickHouse provides execution statistics that help optimize queries:

```ruby
result = client.execute('SELECT * FROM events SAMPLE 0.1')

# Timing information
elapsed_ms = result.elapsed_time
# => 1234 (milliseconds)

# Data read statistics (useful for SAMPLE queries)
rows_read = result.rows_read
# => 5000000 (rows ClickHouse had to examine)

bytes_read = result.bytes_read
# => 52428800 (bytes read from disk/cache)

# Log query statistics
logger.info("Query: #{elapsed_ms}ms, #{rows_read} rows read, #{bytes_read} bytes")

# Performance analysis
if elapsed_ms > 5000
  logger.warn("Slow query detected: #{elapsed_ms}ms")
end

if bytes_read > 1_000_000_000
  logger.warn("Large data access: #{bytes_read / 1024 / 1024}MB read")
end
```

### Result Paging Patterns

Handle large result sets without loading all data:

```ruby
# Pattern 1: Pagination with LIMIT/OFFSET
page = 2
page_size = 100
offset = (page - 1) * page_size

result = client.execute(
  "SELECT * FROM events ORDER BY id LIMIT #{page_size} OFFSET #{offset}"
)

# Pattern 2: Keyset pagination (more efficient for large result sets)
last_id = 0
loop do
  result = client.execute(
    "SELECT * FROM events WHERE id > #{last_id} ORDER BY id LIMIT 1000"
  )

  break if result.empty?

  result.each { |row| process_row(row) }
  last_id = result.last['id']
end

# Pattern 3: Use streaming instead for very large results (see Section 4)
```

### Performance Considerations

**Memory Usage**

Results are loaded entirely into memory. For large result sets (10M+ rows), consider
streaming instead:

```ruby
# BAD: All data loaded into memory
result = client.execute('SELECT * FROM huge_table')  # May exhaust memory
result.each { |row| process(row) }

# GOOD: Stream data one row at a time
client.stream_execute('SELECT * FROM huge_table') { |row| process(row) }
```

**Type Deserialization**

Each row value is deserialized from JSON according to its ClickHouse type:

```ruby
# Type deserialization is automatic but has performance cost
result = client.execute('SELECT timestamp, data FROM events')

# Each timestamp is deserialized to DateTime
# Each data JSON string is kept as string (no automatic parsing)
result.first['timestamp']  # => DateTime object
result.first['data']       # => String (not parsed JSON)
```

### Common Gotchas

**Gotcha 1: Result Encoding Issues**

Ensure your result data is properly encoded:

```ruby
# Issue: Invalid UTF-8 bytes in result
begin
  result = client.execute('SELECT name FROM users')
  names = result.column_values('name')
rescue Encoding::InvalidByteSequenceError => e
  # Likely malformed data in database
  logger.error("Encoding error: #{e.message}")
end
```

**Gotcha 2: Column Name Casing**

ClickHouse column names are case-sensitive:

```ruby
result = client.execute('SELECT user_id FROM users')

# Case must match exactly
value = result.first['user_id']  # ✓ Correct
value = result.first['USER_ID']  # ✗ nil

# Tip: Use column aliases to standardize naming
result = client.execute('SELECT user_id AS id FROM users')
result.first['id']  # Now available as 'id'
```

---

## 4. Streaming Enhancements

Streaming is essential for memory-efficient processing of large result sets. This
section covers advanced streaming patterns and optimizations.

### When to Use Streaming

Streaming trades complexity for memory efficiency. Use streaming when:

- Result set exceeds 100K rows
- Processing each row independently (no full-data transformations)
- Applying to continuous data pipelines
- Available memory is constrained

```ruby
# Threshold: When does streaming become beneficial?
# Result size × average_row_size > available_memory / 10

# Example: 10M rows × 1KB average = 10GB
# If server has 16GB RAM, streaming becomes critical to avoid OOM

# 10M rows × 1KB / (16GB / 10) ≈ 6.2M rows threshold
```

### Basic Streaming

Iterate over results without loading all data:

```ruby
# Block form (recommended: connection held open during block)
client.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
  puts "Processed: #{row['id']}"
end
# Connection automatically returned after block

# Enumerator form (for lazy evaluation)
enumerator = client.stream_execute('SELECT * FROM huge_table')
enumerator.each { |row| process_row(row) }
```

### Lazy Enumeration Patterns

Combine streaming with Ruby's `lazy` for composable operations:

```ruby
# Lazy filtering + mapping + early termination
result = client.stream_execute('SELECT * FROM huge_table')
  .lazy
  .select { |row| row['status'] == 'active' }
  .map { |row| row['id'] }
  .first(100)  # Stop after 100 matching rows

# Memory efficient: Only fetches rows until 100 matches found
# Avoids processing entire huge_table
```

### Batch Processing

Process results in batches without loading entire dataset:

```ruby
# Manual batch processing
batch = []
client.stream_execute('SELECT * FROM events') do |row|
  batch << row
  if batch.size >= 1000
    bulk_insert_to_external_system(batch)
    batch.clear
  end
end

# Process remaining rows
bulk_insert_to_external_system(batch) if batch.any?

# Convenience method: each_batch
client.each_batch('SELECT * FROM events', batch_size: 1000) do |batch|
  # batch is an array of up to 1000 rows
  bulk_insert_to_external_system(batch)
  puts "Processed batch: #{batch.size} rows"
end
```

### Progress Callbacks

Monitor progress during long-running streams:

```ruby
# Track progress with callbacks
rows_processed = 0
batch_count = 0

client.each_batch(
  'SELECT * FROM huge_table',
  batch_size: 5000
) do |batch|
  process_batch(batch)
  rows_processed += batch.size
  batch_count += 1

  if batch_count % 10 == 0
    logger.info("Progress: #{rows_processed} rows processed")
  end
end

logger.info("Completed: #{rows_processed} rows in #{batch_count} batches")
```

For real-time progress bars with large streams:

```ruby
require 'progressbar'

progressbar = ProgressBar.create(
  title: 'Processing Events',
  total: nil,  # Unknown total
  format: '%t: %c rows [%b>%i] %p%% %r rows/sec'
)

client.each_batch('SELECT * FROM events', batch_size: 1000) do |batch|
  process_batch(batch)
  progressbar.progress += batch.size
end

progressbar.finish
```

### Convenience Methods

Helper methods for common streaming patterns:

```ruby
# Stream single values from result
client.each_row('SELECT id, name FROM users') do |row|
  puts "ID: #{row['id']}, Name: #{row['name']}"
end

# Stream and transform
client.each_row('SELECT timestamp, amount FROM transactions') do |row|
  next unless row['amount'].positive?
  process_transaction(row)
end
```

### Connection Handling During Streaming

The connection is held open for the duration of the stream block:

```ruby
# Connection is checked out for the entire block
client.stream_execute('SELECT * FROM huge_table') do |row|
  # Connection held open here
  process_row(row)
  sleep 0.1  # Simulates slow processing
end
# Connection checked back in here

# This means:
# ✓ Other threads can use remaining connections
# ✓ If timeout occurs during stream, exception raised
# ✓ Slow processing holds connection for entire duration
```

Be aware of connection timeouts during slow processing:

```ruby
# Gotcha: Connection timeout during slow stream processing
client.stream_execute('SELECT * FROM events', settings: { max_execution_time: 60 }) do |row|
  process_row(row)  # If this takes > read_timeout, connection breaks
end

# Solution: Increase timeout for streaming operations
config.read_timeout = 300  # 5 minutes for streaming
```

### Error Handling in Streams

Exceptions during streaming close the connection and stop iteration:

```ruby
# Partial failure handling
processed = 0
errors = []

begin
  client.stream_execute('SELECT * FROM events') do |row|
    begin
      process_row(row)
      processed += 1
    rescue => e
      errors << { row: row, error: e }
      next  # Continue to next row on processing error
    end
  end
rescue ClickhouseRuby::ConnectionError => e
  # Connection failed during streaming
  logger.error("Stream connection failed after #{processed} rows: #{e.message}")
rescue ClickhouseRuby::QueryError => e
  # ClickHouse query failed
  logger.error("Query failed after #{processed} rows: #{e.message}")
end

# Log errors encountered
if errors.any?
  logger.warn("Encountered #{errors.size} processing errors")
  errors.each { |e| logger.error(e) }
end

logger.info("Stream completed: #{processed} rows processed")
```

### Compression with Streaming

Compression reduces network bandwidth for large streams:

```ruby
config = ClickhouseRuby::Configuration.new
config.compression = 'gzip'
config.compression_threshold = 1024  # Compress if > 1KB

client = ClickhouseRuby::Client.new(config)

# Large stream automatically compressed
client.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
end

# Benefit: Reduces network traffic by 3-10x for typical data
# Cost: CPU used for compression/decompression
```

### Streaming Gotchas

**Gotcha 1: No FINAL or Aggregation**

Streaming cannot be used with certain query types:

```ruby
# BAD: Cannot use stream with FINAL (deduplication)
client.stream_execute('SELECT * FROM users FINAL') do |row|
  # This will fail or behave unexpectedly
end

# BAD: Cannot use stream with aggregate functions
client.stream_execute('SELECT count(), status FROM users GROUP BY status') do |row|
  # This will fail: aggregates return single result, not stream
end

# GOOD: Stream simple SELECT queries
client.stream_execute('SELECT * FROM users') { |row| process(row) }

# GOOD: Stream with WHERE/PREWHERE/SAMPLE
client.stream_execute(
  'SELECT * FROM users SAMPLE 0.1 WHERE status = ?',
  ['active']
) { |row| process(row) }
```

**Gotcha 2: Connection Held Open**

Long processing times hold the connection open:

```ruby
# BAD: Holds connection for 10 hours
client.stream_execute('SELECT * FROM huge_table') do |row|
  sleep 60  # Simulates slow processing
  process_row(row)
end
# Other threads starved for connections during this time

# GOOD: Batch and release connections
client.each_batch('SELECT * FROM huge_table', batch_size: 10000) do |batch|
  batch.each { |row| slow_process(row) }
  # Connection returned between batches
end
```

**Gotcha 3: No Result Metadata**

Streaming doesn't provide `.elapsed_time`, `.rows_read` etc:

```ruby
# Regular query: has metadata
result = client.execute('SELECT * FROM users')
elapsed = result.elapsed_time  # ✓ Available

# Streaming: no metadata
client.stream_execute('SELECT * FROM users') do |row|
  # No metadata available during streaming
end
```

---

## 5. Configuration Helpers

The Configuration object provides utilities for validation, inspection, and
customization beyond basic attribute accessors.

### Validation

Validate configuration before creating a client:

```ruby
config = ClickhouseRuby::Configuration.new
config.host = 'clickhouse.example.com'
config.port = 8443
config.ssl = true
config.ssl_verify = true

# Validate all settings
config.validate!  # Raises ConfigurationError if invalid

# Common validation checks:
# - Host is not empty
# - Port is 1-65535
# - Timeouts are positive
# - Pool size is > 0

# Usage in initialization
begin
  config.validate!
  client = ClickhouseRuby::Client.new(config)
rescue ClickhouseRuby::ConfigurationError => e
  logger.error("Invalid configuration: #{e.message}")
  exit 1
end
```

### SSL/TLS Helpers

Configure SSL with helpers:

```ruby
# Automatic SSL detection based on port
config = ClickhouseRuby::Configuration.new
config.port = 8443
config.use_ssl?  # => true (automatically detected)

# Check if SSL is enabled
if config.use_ssl?
  logger.info("SSL enabled: #{config.ssl_ca_path || 'system defaults'}")
end

# Set custom CA certificate
config.ssl_ca_path = '/etc/ssl/certs/custom-ca.pem'
config.ssl_verify = true

# Ensure certificate verification
config.ssl_verify = ENV['CLICKHOUSE_SKIP_SSL_VERIFICATION'] != 'true'
```

### Connection Options

Get connection options for advanced use:

```ruby
config = ClickhouseRuby::Configuration.new
config.host = 'clickhouse.prod'
config.port = 8443
config.username = 'admin'
config.password = 'secret'

options = config.to_connection_options
# => {
#   host: 'clickhouse.prod',
#   port: 8443,
#   database: 'default',
#   username: 'admin',
#   password: 'secret',
#   use_ssl: true,
#   ssl_verify: true,
#   ssl_ca_path: nil,
#   connect_timeout: 10,
#   read_timeout: 60,
#   write_timeout: 60
# }

# Use for logging/debugging
logger.debug("Connection options: #{options.inspect}")
```

### Configuration Cloning

Create variations of configuration for different purposes:

```ruby
# Base configuration
base_config = ClickhouseRuby::Configuration.new
base_config.host = ENV['CLICKHOUSE_HOST']
base_config.port = ENV['CLICKHOUSE_PORT'].to_i
base_config.database = 'default'
base_config.pool_size = 10

# Clone for read-only replica with different settings
read_config = base_config.dup
read_config.host = ENV['CLICKHOUSE_REPLICA_HOST']
read_config.pool_size = 20  # More connections for reads

# Clone for writes with higher timeout
write_config = base_config.dup
write_config.write_timeout = 120  # Longer timeout for writes

# Use appropriately
read_client = ClickhouseRuby::Client.new(read_config)
write_client = ClickhouseRuby::Client.new(write_config)
```

### Base URL Construction

Get the connection URL for logging/debugging:

```ruby
config = ClickhouseRuby::Configuration.new
config.host = 'clickhouse.example.com'
config.port = 8443
config.ssl = true

url = config.base_url
# => 'https://clickhouse.example.com:8443'

logger.info("Connecting to ClickHouse at #{url}")
```

### Compression Configuration

Optimize compression settings:

```ruby
# Enable gzip compression
config.compression = 'gzip'
config.compression_threshold = 1024  # Minimum 1KB

# Check if compression is enabled
if config.compression_enabled?
  logger.info("Compression enabled: #{config.compression}")
end

# Tuning for different scenarios
# High-throughput, large batches
config.compression_threshold = 10_000  # Only compress large payloads

# Low-bandwidth environments
config.compression_threshold = 100  # Compress even small responses

# Disable compression if CPU-limited
config.compression = nil
```

### Retry Configuration

Tune retry strategy for unreliable networks:

```ruby
# Default retry configuration
config.max_retries = 3
config.initial_backoff = 1.0        # Start with 1 second
config.backoff_multiplier = 1.6     # Exponential backoff
config.max_backoff = 120.0          # Cap at 2 minutes
config.retry_jitter = :equal        # Add jitter to prevent thundering herd

# Conservative retry for low-latency requirements
config.max_retries = 1              # Only 1 retry
config.initial_backoff = 0.1        # Start immediately

# Aggressive retry for high-reliability requirements
config.max_retries = 5              # Many retries
config.initial_backoff = 2.0        # Wait longer between attempts
config.max_backoff = 60.0           # Cap shorter
```

### Logging Configuration

Control debug output:

```ruby
require 'logger'

config = ClickhouseRuby::Configuration.new
config.logger = Logger.new($stdout)
config.log_level = :debug  # Log all operations

# In Rails
config.logger = Rails.logger
config.log_level = Rails.env.production? ? :info : :debug

# Disable logging
config.logger = nil
```

### Pool and Timeout Settings

Critical for production stability:

```ruby
# Connection limits
config.pool_size = 10         # Concurrent connections
config.pool_timeout = 5       # Wait for available connection

# Socket timeouts (in seconds)
config.connect_timeout = 10   # Establish connection
config.read_timeout = 60      # Wait for response
config.write_timeout = 60     # Send request

# For slow queries or large result sets
config.read_timeout = 300     # 5 minutes for streaming

# For high-latency networks
config.connect_timeout = 30   # Up to 30 seconds to connect
config.read_timeout = 120     # Up to 2 minutes for responses
```

---

## 6. Enhanced Error Information

ClickhouseRuby provides rich error context for debugging and error handling. Understanding
the error hierarchy and recovery strategies is essential for production reliability.

### Error Hierarchy

All errors inherit from `ClickhouseRuby::Error`:

```ruby
ClickhouseRuby::Error
├── ConnectionError
│   ├── ConnectionNotEstablished
│   ├── ConnectionTimeout
│   └── SSLError
├── QueryError
│   ├── SyntaxError
│   ├── StatementInvalid
│   ├── QueryTimeout
│   └── UnknownTable
├── TypeCastError
└── PoolError
```

### QueryError Rich Context

QueryError includes multiple attributes for debugging:

```ruby
begin
  client.execute('SELECT * FROM nonexistent_table')
rescue ClickhouseRuby::QueryError => e
  # Rich context available
  puts e.message           # => "Table nonexistent_table doesn't exist"
  puts e.code             # => 60 (ClickHouse error code)
  puts e.http_status      # => 404
  puts e.sql              # => "SELECT * FROM nonexistent_table"
  puts e.original_error   # => Original Net::HTTP exception

  # Log all context
  logger.error("Query failed: #{e.detailed_message}")
  # => "Query failed: Table nonexistent_table doesn't exist | Code: 60 |
  #     HTTP Status: 404 | SQL: SELECT * FROM nonexistent_table"
end
```

### Specific Error Classes and Recovery

Handle different error types with appropriate recovery strategies:

```ruby
# Syntax errors are not retried (client error)
begin
  client.execute('SELCT * FROM users')  # Typo
rescue ClickhouseRuby::SyntaxError => e
  logger.error("SQL syntax error: #{e.message}")
  # Fix the query and retry with corrected SQL
rescue ClickhouseRuby::QueryError => e
  logger.error("Query error: #{e.message}")
  # Determine cause and recover
end

# Connection errors may be transient
begin
  client.execute('SELECT 1')
rescue ClickhouseRuby::ConnectionError => e
  logger.warn("Connection error: #{e.message}")
  # May retry automatically (see retry configuration)
  # Or implement custom retry logic
rescue ClickhouseRuby::ConnectionTimeout => e
  logger.warn("Connection timeout: #{e.message}")
  # Increase timeout or reduce query complexity
end

# Comprehensive error handling
begin
  results = client.stream_execute('SELECT * FROM events')
  results.each { |row| process_row(row) }
rescue ClickhouseRuby::QueryTimeout => e
  logger.error("Query timed out: #{e.message}")
  # Reduce dataset, add SAMPLE, or increase timeout
rescue ClickhouseRuby::ConnectionError => e
  logger.error("Connection lost: #{e.message}")
  # Check network, retry with backoff
rescue ClickhouseRuby::TypeCastError => e
  logger.error("Type conversion failed: #{e.message}")
  # Check data types, add custom type handlers
rescue ClickhouseRuby::PoolError => e
  logger.error("Connection pool exhausted: #{e.message}")
  # Increase pool size or reduce concurrent operations
end
```

### ClickHouse Error Code Mapping

ClickhouseRuby maps 30+ ClickHouse error codes to specific exceptions:

```ruby
# Error code reference (common ones)
# 60: UnknownTable
# 62: UnknownDatabase
# 137: QueryTimeout
# 159: QueryNotAllowedDuringMaintenance
# 199: UnexpectedClusterUpdate
# 203: DataTypeIncompatible
# 210: ArgumentOutOfBounds
# 243: StatementInvalid (Unknown identifier)

begin
  client.execute('SELECT unknown_column FROM users')
rescue ClickhouseRuby::StatementInvalid => e
  puts "Error #{e.code}: #{e.message}"
  # => "Error 47: Column unknown_column doesn't exist"
end

# Log error code for debugging
begin
  client.execute(sql)
rescue ClickhouseRuby::QueryError => e
  logger.error("ClickHouse error #{e.code}: #{e.message}")
end
```

### Connection Errors and Retry Implications

Connection errors may be retried automatically:

```ruby
config = ClickhouseRuby::Configuration.new
config.max_retries = 3
config.initial_backoff = 1.0
config.backoff_multiplier = 1.6

client = ClickhouseRuby::Client.new(config)

# This automatically retries on transient failures
begin
  result = client.execute('SELECT 1')
  # Internally: try 1 fails (network) → wait 1s → try 2 fails → wait 1.6s
  # → try 3 succeeds
rescue ClickhouseRuby::ConnectionError => e
  # Only raised if all retries exhausted
  logger.error("All retries failed: #{e.message}")
end

# NOT retried (client errors):
# - QueryError (syntax errors, invalid statements)
# - HTTP 4xx (except 429)
# - TypeCastError

# Retried (transient errors):
# - ConnectionError, timeout
# - HTTP 5xx
# - HTTP 429 (rate limit)
```

### TypeCastError Debugging

Type conversion failures provide context:

```ruby
# Custom type implementation with validation
begin
  result = client.execute('SELECT status FROM events')
  result.each do |row|
    # If status value cannot be cast to expected type
    status = row['status']  # May raise TypeCastError
  end
rescue ClickhouseRuby::TypeCastError => e
  logger.error("Type casting failed: #{e.message}")
  logger.error("Original error: #{e.original_error}")
  # Check:
  # - Data type definition matches ClickHouse schema
  # - Data integrity (no null values in non-nullable fields)
  # - Custom type handlers are registered
end
```

### Pool Errors and Tuning

Pool-related errors indicate resource constraints:

```ruby
begin
  result = client.execute('SELECT * FROM huge_table')
rescue ClickhouseRuby::PoolError => e
  logger.error("Pool error: #{e.message}")
  # Symptoms:
  # - All connections in use (increase pool_size)
  # - Connection timeout (reduce pool_timeout or increase pool_size)
  # - Connection leak (ensure proper cleanup)
end

# Pool stats help diagnose issues
stats = client.pool_stats
if stats[:available] == 0
  logger.warn("All connections in use: #{stats}")
  # Increase pool_size or reduce query concurrency
end

if stats[:failed_checks] > 0
  logger.warn("Pool health checks failing: #{stats}")
  # Check network to ClickHouse, restart connections
end
```

### Error Handling Best Practices

Comprehensive error handling for production:

```ruby
def safe_query(sql, max_retries: 3)
  retry_count = 0

  begin
    return client.execute(sql)
  rescue ClickhouseRuby::SyntaxError => e
    logger.error("Syntax error in query: #{e.sql}")
    raise  # Don't retry syntax errors
  rescue ClickhouseRuby::QueryTimeout => e
    logger.warn("Query timeout (#{e.code}): #{e.message}")
    raise  # Don't retry timeouts
  rescue ClickhouseRuby::ConnectionError => e
    retry_count += 1
    if retry_count <= max_retries
      logger.warn("Connection error (attempt #{retry_count}/#{max_retries}): #{e.message}")
      sleep 2 ** retry_count  # Exponential backoff
      retry
    else
      logger.error("Connection error after #{max_retries} retries: #{e.message}")
      raise
    end
  rescue ClickhouseRuby::QueryError => e
    logger.error("Query error #{e.code}: #{e.detailed_message}")
    raise
  end
end

# Usage
begin
  result = safe_query('SELECT * FROM users')
rescue ClickhouseRuby::Error => e
  logger.error("Unrecoverable error: #{e.message}")
  # Handle gracefully (return empty result, fall back to cache, etc)
end
```

### Root Cause Investigation

Use original_error for debugging:

```ruby
begin
  client.execute('SELECT 1')
rescue ClickhouseRuby::ConnectionError => e
  puts "ClickhouseRuby Error: #{e.message}"
  puts "Original cause: #{e.original_error.class}: #{e.original_error.message}"
  puts "Backtrace:"
  puts e.original_error.backtrace.first(10)

  # Example output:
  # ClickhouseRuby Error: Failed to establish connection
  # Original cause: Errno::ECONNREFUSED: Connection refused
  # Backtrace: ...
end
```

---

## 7. Type System Internals

The type system handles bidirectional conversion between Ruby and ClickHouse types.
Understanding the internals allows creating custom types for specialized use cases.

### NullSafe Module Pattern

The NullSafe module automatically wraps types to handle nil values:

```ruby
# NullSafe wraps any type to support nil
class CustomType
  include ClickhouseRuby::Types::NullSafe

  def deserialize(value)
    return nil if value.nil?
    # Custom deserialization
  end

  def serialize(value)
    return nil if value.nil?
    # Custom serialization
  end
end

# Usage
type = CustomType.new
type.deserialize(nil)   # => nil (handled by NullSafe)
type.deserialize('foo') # => custom deserialization result
```

### StringParser Utilities

The StringParser module provides utilities for parsing complex type strings:

```ruby
require 'clickhouse_ruby/types/string_parser'

# Parse nested type definitions
parser = ClickhouseRuby::Types::StringParser.new

# Simple types
parser.consume_identifier  # Parses 'String', 'UInt64', etc

# Parameterized types with nested arguments
parsed = parser.parse_nested_type_string('Map(String, Array(Tuple(Int32, String)))')
# Recursively parses and returns structure

# Use in custom type registration
class CustomTypeParser
  def parse(type_string)
    parser = ClickhouseRuby::Types::StringParser.new(type_string)
    # Implement custom parsing logic using parser utilities
  end
end
```

### Type Registry and Registration

Register custom types for automatic deserialization:

```ruby
# Register a custom type in the registry
ClickhouseRuby::Types::Registry.register('CustomJSON', CustomJSONType)

# After registration, ClickhouseRuby automatically uses CustomJSONType
# when encountering CustomJSON type in query results
result = client.execute('SELECT json_data FROM my_table')
# json_data values deserialized using CustomJSONType

# Check if type is registered
if ClickhouseRuby::Types::Registry.registered?('CustomJSON')
  type_class = ClickhouseRuby::Types::Registry.get('CustomJSON')
  puts "Type class: #{type_class}"
end
```

### Type Interface

Custom types must implement this interface:

```ruby
class CustomType < ClickhouseRuby::Types::Base
  # Cast Ruby value to ClickHouse format before sending
  # @param value [Object] Ruby value
  # @return [Object] value ready for ClickHouse
  def cast(value)
    value  # Identity by default
  end

  # Deserialize ClickHouse response value to Ruby
  # @param value [Object] value from JSONCompact response
  # @return [Object] deserialized Ruby value
  def deserialize(value)
    value
  end

  # Serialize Ruby value for insert/command
  # @param value [Object] Ruby value
  # @return [Object] serializable value
  def serialize(value)
    value
  end
end
```

### AST-Based Parser for Complex Types

The parser handles nested types correctly using recursive descent:

```ruby
# Example: Parse complex nested type
parser = ClickhouseRuby::Types::Parser.new
ast = parser.parse('Map(String, Array(Tuple(Int32, String)))')

# Result structure:
# {
#   type: 'Map',
#   args: [
#     { type: 'String' },
#     {
#       type: 'Array',
#       args: [{
#         type: 'Tuple',
#         args: [
#           { type: 'Int32' },
#           { type: 'String' }
#         ]
#       }]
#     }
#   ]
# }

# Utility: Validate type string
begin
  ast = parser.parse(type_string)
rescue ClickhouseRuby::Types::Parser::ParseError => e
  logger.error("Invalid type string: #{e.message}")
end
```

### Creating Custom Types

Example: Custom JSON type with automatic parsing:

```ruby
require 'json'

class CustomJSONType < ClickhouseRuby::Types::Base
  def deserialize(value)
    return nil if value.nil?
    # Parse JSON string to Hash
    JSON.parse(value)
  rescue JSON::ParserError => e
    raise ClickhouseRuby::TypeCastError.new(
      "Failed to parse JSON: #{e.message}",
      original_error: e
    )
  end

  def serialize(value)
    return nil if value.nil?
    value.is_a?(String) ? value : JSON.generate(value)
  end
end

# Register the type
ClickhouseRuby::Types::Registry.register('CustomJSON', CustomJSONType)

# Use in queries
result = client.execute('SELECT id, config::CustomJSON FROM settings')
result.first['config']  # => Hash (automatically parsed from JSON)
```

### Type Metadata and Introspection

Inspect types at runtime:

```ruby
# Get type for a column from result
result = client.execute('SELECT status FROM events')
type_obj = result.types[0]

# Type introspection
puts type_obj.class.name           # => 'ClickhouseRuby::Types::String'
puts type_obj.nullable?            # => false (or true for Nullable type)

# For complex types
result = client.execute('SELECT tags FROM posts')
# tags is Array(String)
type_obj = result.types[0]
puts type_obj.class.name           # => 'ClickhouseRuby::Types::Array'
puts type_obj.inner_type.class.name # => 'ClickhouseRuby::Types::String'
```

### Type System Performance Notes

Type deserialization has performance implications:

```ruby
# Benchmark: Type deserialization cost
require 'benchmark'

result = client.execute('SELECT * FROM events LIMIT 100000')

time = Benchmark.realtime do
  result.each do |row|
    # Each row deserialized according to column types
    row['timestamp']  # DateTime deserialization
    row['tags']       # Array deserialization
    row['metadata']   # Nested Map deserialization
  end
end

puts "Deserialization: #{time}s for 100K rows"

# Optimization: Deserialize only needed columns
result = client.execute('SELECT id, name FROM events LIMIT 100000')
# Only String types, faster deserialization than with nested types

# Optimization: Use simpler types when possible
# Prefer String over JSON (no parsing)
# Prefer Array(String) over Array(JSON) (fewer deserializations)
```

### Gotchas

**Gotcha 1: Case Sensitivity**

ClickHouse type names are case-sensitive:

```ruby
# GOOD
ClickhouseRuby::Types::Registry.register('MyType', MyType)

# BAD: Won't match if ClickHouse returns 'MyType'
ClickhouseRuby::Types::Registry.register('mytype', MyType)

# Verify exact case match
result = client.execute('SELECT my_column FROM table')
type_name = result.column_types['my_column'].class.name
```

**Gotcha 2: Nesting Depth**

Very deeply nested types may cause parser stack overflow:

```ruby
# This is fine
'Array(Array(Array(String)))'

# This could be problematic
'Array(Array(Array(Array(Array(Array(Array(Array(String))))))))'

# ClickHouse practical limit is usually 100+ levels, not a real concern
```

**Gotcha 3: Custom Type Registration Timing**

Register custom types before using them:

```ruby
# BAD: Type not registered yet
result = client.execute('SELECT custom_data FROM table')

# Register AFTER first query fails
ClickhouseRuby::Types::Registry.register('CustomData', CustomType)

# GOOD: Register in initializer
# In config/initializers/clickhouse.rb
ClickhouseRuby::Types::Registry.register('CustomJSON', CustomJSONType)
ClickhouseRuby::Types::Registry.register('CustomCSV', CustomCSVType)

# Then queries work correctly
result = client.execute('SELECT custom_json FROM table')
```

---

## See Also

- **[README.md](../README.md)** - Basic usage and quick start
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - System design and internals
- **[ACTIVE_RECORD.md](./ACTIVE_RECORD.md)** - ActiveRecord integration guide
- **[ClickHouse Documentation](https://clickhouse.com/docs)** - Official ClickHouse docs
