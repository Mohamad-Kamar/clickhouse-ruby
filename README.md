# ClickhouseRuby

[![Tests](https://github.com/Mohamad-Kamar/clickhouse-ruby/actions/workflows/test.yml/badge.svg)](https://github.com/Mohamad-Kamar/clickhouse-ruby/actions/workflows/test.yml)
[![Gem Version](https://badge.fury.io/rb/clickhouse-ruby.svg)](https://badge.fury.io/rb/clickhouse-ruby)
[![Downloads](https://img.shields.io/gem/dt/clickhouse-ruby.svg)](https://rubygems.org/gems/clickhouse-ruby)

A lightweight Ruby client for ClickHouse with optional ActiveRecord integration.

## Why ClickhouseRuby?

ClickhouseRuby is designed from the ground up with production reliability and developer experience in mind. Here's what sets it apart:

**🔒 Security & Reliability**
- **SSL verification enabled by default** - Secure by default, unlike alternatives that require explicit configuration
- **Never silently fails** - All errors are properly raised and propagated (fixes [clickhouse-activerecord #230](https://github.com/patrikx3/clickhouse-activerecord/issues/230))
- **Comprehensive error hierarchy** - 30+ specific error classes mapped from ClickHouse error codes

**⚡ Performance & Architecture**
- **Zero runtime dependencies** - Uses only Ruby stdlib, making it lightweight and fully auditable
- **AST-based type parser** - Handles complex nested types correctly (Array(Tuple(String, UInt64)), etc.) unlike regex-based parsers
- **Thread-safe connection pooling** - Built-in pool with health checks and proper resource management
- **Result streaming** - Process millions of rows with constant memory usage

**🛠️ Developer Experience**
- **Clean, intuitive API** - Simple methods for queries, inserts, and DDL operations
- **Optional ActiveRecord integration** - Familiar model-based access when you need it
- **ClickHouse-specific query extensions** - PREWHERE, FINAL, SAMPLE, and SETTINGS DSL built-in
- **Comprehensive type system** - Full support for all ClickHouse types including Nullable, Array, Map, Tuple, Enum, Decimal

**📊 Production Ready**
- **Automatic retries** - Configurable exponential backoff for transient failures
- **HTTP compression** - Reduce bandwidth for large payloads
- **Connection health monitoring** - Pool statistics and health checks
- **Extensive test coverage** - 80%+ coverage with both unit and integration tests

## Features

**Core (v0.1.0)**
- **Simple HTTP client** - Clean API for queries, commands, and bulk inserts
- **Connection pooling** - Built-in connection pool with health checks
- **Type system** - Full support for ClickHouse types including Nullable, Array, Map, Tuple
- **Proper error handling** - Never silently ignores errors (fixes clickhouse-activerecord #230)
- **SSL/TLS support** - Certificate verification enabled by default
- **ActiveRecord integration** - Optional familiar model-based access

**Enhanced (v0.2.0)**
- **Enum & Decimal types** - Fixed-set values and arbitrary precision arithmetic
- **Query optimization** - PREWHERE clause, FINAL deduplication, SAMPLE approximation
- **Performance** - HTTP compression, result streaming, automatic retries with backoff
- **Query control** - Per-query SETTINGS DSL for ClickHouse configuration

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'clickhouse-ruby'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install clickhouse-ruby
```

## Quick Start

```ruby
require 'clickhouse_ruby'

# Configure the client
config = ClickhouseRuby::Configuration.new
config.host = 'localhost'
config.port = 8123
config.database = 'default'

# Create a client
client = ClickhouseRuby::Client.new(config)

# Execute a query
result = client.execute('SELECT 1 + 1 AS result')
puts result.first['result'] # => 2

# Insert data
client.insert('events', [
  { date: '2024-01-01', event_type: 'click', count: 100 },
  { date: '2024-01-02', event_type: 'view', count: 250 }
])
```

## Configuration

### Basic Configuration

```ruby
ClickhouseRuby.configure do |config|
  config.host = 'localhost'
  config.port = 8123
  config.database = 'default'
  config.username = 'default'
  config.password = ''
  config.ssl = false
  config.connect_timeout = 10
  config.read_timeout = 60
end

# Use the default client
client = ClickhouseRuby.client
```

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `host` | ClickHouse server hostname | `localhost` |
| `port` | HTTP interface port | `8123` |
| `database` | Default database | `default` |
| `username` | Authentication username | `default` |
| `password` | Authentication password | `nil` |
| `ssl` | Enable HTTPS | `false` |
| `ssl_verify` | Verify SSL certificates | `true` |
| `ssl_ca_path` | Custom CA certificate file path | `nil` |
| `connect_timeout` | Connection timeout in seconds | `10` |
| `read_timeout` | Read timeout in seconds | `60` |
| `write_timeout` | Write timeout in seconds | `60` |
| `pool_size` | Connection pool size | `5` |
| `log_level` | Logger level (`:debug`, `:info`, `:warn`, `:error`) | `:info` |
| `default_settings` | Global ClickHouse settings for all queries | `{}` |
| `pool_timeout` | Wait time for available connection in seconds | `5` |
| `retry_jitter` | Jitter strategy (`:full`, `:equal`, `:none`) | `:equal` |

### Environment Variables

ClickhouseRuby can be configured via environment variables:

```bash
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8123
CLICKHOUSE_DATABASE=default
CLICKHOUSE_USERNAME=default
CLICKHOUSE_PASSWORD=secret
CLICKHOUSE_SSL=false
```

### v0.2.0 Enhancements

**HTTP Compression** - Reduce bandwidth for large payloads:
```ruby
ClickhouseRuby.configure do |config|
  config.compression = 'gzip'
  config.compression_threshold = 1024  # Only compress > 1KB
end
```

**Retry Logic** - Automatic retries with exponential backoff:
```ruby
ClickhouseRuby.configure do |config|
  config.max_retries = 3
  config.initial_backoff = 1.0
  config.backoff_multiplier = 1.6
  config.max_backoff = 120
end
```

**Result Streaming** - Process large results with constant memory:
```ruby
client.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
end
```

**ActiveRecord Query Extensions** - ClickHouse-specific query methods:
```ruby
# Query optimization
Event.prewhere(date: Date.today).where(status: 'active')

# Deduplication
User.final.where(id: 123)

# Approximate queries
Event.sample(0.1).count  # 10% sample

# Per-query configuration
Event.settings(max_threads: 4).where(active: true)
```

See [docs/features/README.md](docs/features/README.md) for detailed documentation on all v0.2.0 features.

## Usage

### Querying Data

```ruby
# Simple query - returns Result object
result = client.execute('SELECT * FROM events LIMIT 10')
result.each { |row| puts row['event_type'] }

# Access columns and types
result.columns  # => ['id', 'event_type', 'count']
result.types    # => ['UInt64', 'String', 'UInt32']

# Query with settings
result = client.execute(
  'SELECT * FROM events',
  settings: { max_rows_to_read: 1_000_000 }
)
```

### Result Metadata

Access query metadata and result information:

```ruby
result = client.execute('SELECT * FROM events LIMIT 100')

# Query execution metadata
result.elapsed_time    # => 0.042 (seconds)
result.rows_read       # => 100
result.bytes_read      # => 8500
result.rows_written    # => 0 (for SELECT queries)
result.bytes_written   # => 0

# Result size information
result.count           # => 100 (alias for size/length)
result.size            # => 100
result.length          # => 100

# Column information
result.columns         # => ["id", "event_type", "count"]
result.column_types    # => ["UInt64", "String", "UInt32"]
result.types           # => ["UInt64", "String", "UInt32"]

# Row access methods
result.first           # => {"id" => 1, "event_type" => "click", "count" => 100}
result.last            # => {"id" => 100, "event_type" => "view", "count" => 50}
result[5]              # => {"id" => 5, "event_type" => "click", "count" => 75}

# Get all values for a specific column
result.column_values("event_type")  # => ["click", "view", "click", ...]
```

### DDL Commands

```ruby
# Create table
client.command(<<~SQL)
  CREATE TABLE events (
    date Date,
    event_type String,
    count UInt32
  ) ENGINE = MergeTree()
  ORDER BY date
SQL

# Drop table
client.command('DROP TABLE IF EXISTS events')
```

### Inserting Data

```ruby
# Insert hash array (uses efficient JSONEachRow format)
client.insert('events', [
  { date: '2024-01-01', event_type: 'click', count: 100 },
  { date: '2024-01-02', event_type: 'view', count: 250 }
])

# Insert with explicit columns
client.insert('events', data, columns: ['date', 'event_type', 'count'])
```

### Connection Management

```ruby
# Check connection
client.ping # => true

# Get server version
client.server_version # => "24.1.1.123"

# Get pool statistics
client.pool_stats # => {
#   size: 5,                    # Total pool capacity
#   available: 4,               # Connections ready to use
#   in_use: 1,                  # Connections currently in use
#   total_connections: 5,       # Total connections created
#   total_checkouts: 150,       # Lifetime pool checkout count
#   total_timeouts: 0,          # Timeouts waiting for connection
#   uptime_seconds: 3600.5      # Seconds since pool created
# }

# Close all connections
client.close
```

### Advanced Client Methods

#### Batch Processing

Process large query results in batches to manage memory efficiently:

```ruby
# Process 500 rows at a time
client.each_batch('SELECT * FROM huge_table', batch_size: 500) do |batch|
  # batch is an array of hashes (max 500 rows)
  puts "Processing batch of #{batch.size} rows"
  insert_to_cache(batch)
end

# Default batch size is 500 rows
client.each_batch('SELECT * FROM data') { |batch| process(batch) }
```

#### Row-by-Row Processing

Process results one row at a time for maximum memory efficiency:

```ruby
# Stream processing - constant memory usage
client.each_row('SELECT * FROM massive_table') do |row|
  # row is a single hash
  puts "Processing: #{row['id']}"
  update_statistics(row)
end

# Returns Enumerator if no block given
rows = client.each_row('SELECT * FROM table')
rows.each { |row| puts row['name'] }
```

#### Connection Aliases

Additional connection management methods:

```ruby
# Disconnect all connections in the pool
client.disconnect

# Check if client is connected
client.connected?  # => true
```

#### Module-Level Methods

Quick access without explicit client instance:

```ruby
# Execute query using default client
result = ClickhouseRuby.execute('SELECT 1 AS num')

# Insert data using default client
ClickhouseRuby.insert('events', [
  { date: '2024-01-01', event_type: 'click' }
])

# Ping default client
ClickhouseRuby.ping  # => true
```

**Performance Note**: Batch and row-by-row processing methods use result streaming internally,
which maintains constant memory usage regardless of result size. Use these methods for queries
that return millions of rows to prevent memory exhaustion.

## Type Support

ClickhouseRuby supports all ClickHouse types:

| ClickHouse Type | Ruby Type |
|-----------------|-----------|
| Int8-Int64, UInt8-UInt64 | Integer |
| Float32, Float64 | Float |
| String, FixedString | String |
| Date, Date32 | Date |
| DateTime, DateTime64 | Time |
| UUID | String |
| Bool | Boolean |
| Nullable(T) | T or nil |
| Array(T) | Array |
| Map(K, V) | Hash |
| Tuple(T...) | Array |
| LowCardinality(T) | T |

## Error Handling

```ruby
begin
  client.execute('SELECT * FROM nonexistent_table')
rescue ClickhouseRuby::UnknownTable => e
  puts "Table not found: #{e.message}"
  puts "Error code: #{e.code}"        # ClickHouse error code
  puts "HTTP status: #{e.http_status}" # HTTP response code
rescue ClickhouseRuby::ConnectionError => e
  puts "Connection failed: #{e.message}"
rescue ClickhouseRuby::QueryError => e
  puts "Query failed: #{e.message}"
end
```

### Error Classes

- `ClickhouseRuby::Error` - Base error class
- `ClickhouseRuby::ConnectionError` - Connection issues
- `ClickhouseRuby::ConnectionTimeout` - Timeout errors
- `ClickhouseRuby::QueryError` - Query execution errors
- `ClickhouseRuby::SyntaxError` - SQL syntax errors
- `ClickhouseRuby::UnknownTable` - Table doesn't exist
- `ClickhouseRuby::UnknownColumn` - Column doesn't exist
- `ClickhouseRuby::UnknownDatabase` - Database doesn't exist

## ActiveRecord Integration

ClickhouseRuby provides optional ActiveRecord integration for familiar model-based access.

```ruby
# config/initializers/clickhouse_ruby.rb
require 'clickhouse_ruby/active_record'

ClickhouseRuby::ActiveRecord.establish_connection(
  host: 'localhost',
  database: 'analytics'
)

# app/models/event.rb
class Event < ClickhouseRuby::ActiveRecord::Base
  self.table_name = 'events'
end

# Usage
Event.where(date: '2024-01-01').limit(10).each do |event|
  puts event.event_type
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

### Running Tests

```bash
# Start ClickHouse
docker-compose up -d

# Run unit tests only
bundle exec rspec spec/unit

# Run all tests including integration
CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec
```

## Requirements

- Ruby >= 2.6.0
- ClickHouse >= 20.x (tested with 24.x)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Mohamad-Kamar/clickhouse-ruby.

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).

## Documentation

Full documentation is available at [RubyDoc](https://rubydoc.info/gems/clickhouse-ruby).
