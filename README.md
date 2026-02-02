# ClickhouseRuby

[![Tests](https://github.com/Mohamad-Kamar/clickhouse-ruby/actions/workflows/test.yml/badge.svg)](https://github.com/Mohamad-Kamar/clickhouse-ruby/actions/workflows/test.yml)
[![Gem Version](https://badge.fury.io/rb/clickhouse-ruby.svg)](https://badge.fury.io/rb/clickhouse-ruby)
[![Downloads](https://img.shields.io/gem/dt/clickhouse-ruby.svg)](https://rubygems.org/gems/clickhouse-ruby)

A lightweight Ruby client for ClickHouse with optional ActiveRecord integration.

## Why ClickhouseRuby?

- **SSL verification enabled by default** - Secure by default
- **Never silently fails** - All errors properly raised (fixes [clickhouse-activerecord #230](https://github.com/patrikx3/clickhouse-activerecord/issues/230))
- **Zero runtime dependencies** - Uses only Ruby stdlib
- **AST-based type parser** - Handles complex nested types correctly
- **Thread-safe connection pooling** - Built-in pool with health checks
- **ClickHouse-specific extensions** - PREWHERE, FINAL, SAMPLE, SETTINGS

## Installation

```ruby
# Gemfile
gem 'clickhouse-ruby'
```

```bash
bundle install
```

## Quick Start

```ruby
require 'clickhouse_ruby'

# Configure
ClickhouseRuby.configure do |config|
  config.host = 'localhost'
  config.port = 8123
  config.database = 'default'
end

# Query
client = ClickhouseRuby.client
result = client.execute('SELECT 1 + 1 AS result')
puts result.first['result'] # => 2

# Insert
client.insert('events', [
  { date: '2024-01-01', event_type: 'click', count: 100 },
  { date: '2024-01-02', event_type: 'view', count: 250 }
])
```

## Features

**Core (v0.1.0)**
- Simple HTTP client with connection pooling
- Full type system (Nullable, Array, Map, Tuple)
- Comprehensive error handling
- SSL/TLS support
- Optional ActiveRecord integration

**Enhanced (v0.2.0)**
- Enum & Decimal types
- PREWHERE, FINAL, SAMPLE query extensions
- HTTP compression, result streaming
- Automatic retries with backoff

**Production (v0.3.0)**
- Observability & instrumentation
- Migration generators
- Health checks
- Performance benchmarking

## Configuration

```ruby
ClickhouseRuby.configure do |config|
  config.host = 'localhost'
  config.port = 8123
  config.database = 'default'
  config.username = 'default'
  config.password = ''
  config.ssl = false
  config.pool_size = 5
  config.read_timeout = 60
end
```

Or via environment variables:

```bash
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8123
CLICKHOUSE_DATABASE=default
```

See [Configuration Reference](docs/reference/configuration.md) for all options.

## Usage

### Queries

```ruby
result = client.execute('SELECT * FROM events LIMIT 10')
result.each { |row| puts row['event_type'] }
result.columns  # => ['id', 'event_type', 'count']
result.types    # => ['UInt64', 'String', 'UInt32']
```

### DDL

```ruby
client.command(<<~SQL)
  CREATE TABLE events (
    date Date,
    event_type String,
    count UInt32
  ) ENGINE = MergeTree()
  ORDER BY date
SQL
```

### Large Results

```ruby
# Stream row by row (constant memory)
client.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
end

# Batch processing
client.each_batch('SELECT * FROM huge_table', batch_size: 1000) do |batch|
  process_batch(batch)
end
```

See [Querying Guide](docs/guides/querying.md) for more.

## ActiveRecord Integration

```ruby
require 'clickhouse_ruby/active_record'

ClickhouseRuby::ActiveRecord.establish_connection(
  host: 'localhost',
  database: 'analytics'
)

class Event < ClickhouseRuby::ActiveRecord::Base
  self.table_name = 'events'
end

# Query
Event.where(date: Date.today).count

# ClickHouse-specific extensions
Event.prewhere(date: Date.today).where(status: 'active')  # PREWHERE
User.final.where(id: 123)                                  # FINAL
Event.sample(0.1).count                                    # SAMPLE
Event.settings(max_threads: 4).all                         # SETTINGS
```

See [ActiveRecord Guide](docs/guides/activerecord.md) for complete documentation.

## Error Handling

```ruby
begin
  client.execute('SELECT * FROM nonexistent_table')
rescue ClickhouseRuby::UnknownTable => e
  puts "Table not found: #{e.message}"
  puts "Error code: #{e.code}"
rescue ClickhouseRuby::ConnectionError => e
  puts "Connection failed: #{e.message}"
end
```

See [Error Reference](docs/reference/errors.md) for all error classes.

## Type Support

| ClickHouse Type | Ruby Type |
|-----------------|-----------|
| Int8-Int64, UInt8-UInt64 | Integer |
| Float32, Float64 | Float |
| String | String |
| Date, DateTime | Date, Time |
| Nullable(T) | T or nil |
| Array(T) | Array |
| Map(K, V) | Hash |
| Enum8, Enum16 | String |
| Decimal(P,S) | BigDecimal |

See [Types Reference](docs/reference/types.md) for complete mapping.

## Documentation

| Section | Description |
|---------|-------------|
| [Getting Started](docs/getting-started/) | Installation and tutorials |
| [Guides](docs/guides/) | How-to guides for specific tasks |
| [Reference](docs/reference/) | Configuration and API reference |
| [Concepts](docs/concepts/) | Architecture and design |
| [Examples](docs/examples/) | Real-world patterns |

## Requirements

- Ruby >= 2.6.0
- ClickHouse >= 20.x (tested with 24.x)

## Development

```bash
# Start ClickHouse
docker-compose up -d

# Run tests
bundle exec rake spec

# Run linter
bundle exec rake rubocop
```

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License. See [LICENSE](LICENSE).
