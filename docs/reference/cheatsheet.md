# Quick Reference

Quick reference guide for common ClickhouseRuby operations and configurations.

## Client Initialization

```ruby
# Quick setup
require 'clickhouse_ruby'

ClickhouseRuby.configure do |c|
  c.host = "localhost"
  c.port = 8123
  c.database = "default"
  c.username = "default"
  c.password = ""
end

# Get client
client = ClickhouseRuby.client
```

## Common Operations

### Query

```ruby
# Execute query
result = client.execute("SELECT * FROM events LIMIT 10")
result.each { |row| puts row['event_type'] }

# Query with settings
result = client.execute(
  "SELECT * FROM events",
  settings: { max_rows_to_read: 1_000_000 }
)
```

### Insert

```ruby
# Insert single row
client.insert("events", [{id: 1, name: "test"}])

# Bulk insert
client.insert("events", [
  {date: '2024-01-01', event_type: 'click', count: 100},
  {date: '2024-01-02', event_type: 'view', count: 250}
])
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

# Alter table
client.command('ALTER TABLE events ADD COLUMN user_id UInt64')
```

### Health Check

```ruby
# Basic ping
client.ping  # => true

# Comprehensive health check
health = client.health_check
if health[:status] == :healthy
  # System is healthy
end

# Pool statistics
stats = client.pool_stats
```

## ActiveRecord Usage

### Setup

```ruby
# config/initializers/clickhouse.rb
require "clickhouse_ruby/active_record"

class ClickhouseRecord < ActiveRecord::Base
  self.abstract_class = true
  establish_connection(
    adapter: 'clickhouse',
    host: 'localhost',
    database: 'analytics'
  )
end
```

### Queries

```ruby
class Event < ClickhouseRecord
  self.table_name = "events"
end

# Basic queries
Event.where(event_type: "click").limit(10)
Event.where(user_id: 123).count

# ClickHouse-specific extensions
Event.prewhere(date: Date.today).where(status: 'active')
Event.final.where(id: 123)
Event.sample(0.1).count
Event.settings(max_threads: 4).all
```

### Migrations

```bash
# Generate migration
rails generate clickhouse:migration CreateEvents \
  id:uuid \
  event_type:string \
  created_at:datetime \
  --engine=MergeTree \
  --order-by="(event_type, created_at)" \
  --partition-by="toYYYYMM(created_at)"
```

## Streaming

```ruby
# Stream large results row by row
client.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
end

# Batch processing
client.each_batch('SELECT * FROM huge_table', batch_size: 1000) do |batch|
  process_batch(batch)
end
```

## Query Analysis

```ruby
# Explain query plan
plan = client.explain('SELECT * FROM events WHERE date = today()')

# Explain pipeline
pipeline = client.explain('SELECT * FROM events', type: :pipeline)

# Estimate cost
estimate = client.explain('SELECT count() FROM events', type: :estimate)
```

## Configuration

### Production Configuration

```ruby
ClickhouseRuby.configure do |config|
  # Connection
  config.host = ENV['CLICKHOUSE_HOST']
  config.port = ENV['CLICKHOUSE_PORT']&.to_i || 8123
  config.database = ENV['CLICKHOUSE_DATABASE'] || 'default'
  config.username = ENV['CLICKHOUSE_USERNAME']
  config.password = ENV['CLICKHOUSE_PASSWORD']
  
  # SSL
  config.ssl = ENV['CLICKHOUSE_SSL'] == 'true'
  config.ssl_verify = true
  
  # Timeouts
  config.connect_timeout = 10
  config.read_timeout = 300
  config.write_timeout = 300
  
  # Pool
  config.pool_size = 10
  config.pool_timeout = 5
  
  # Performance
  config.compression = 'gzip'
  config.compression_threshold = 1024
  config.max_retries = 3
end
```

## Error Handling

```ruby
begin
  client.execute('SELECT * FROM nonexistent_table')
rescue ClickhouseRuby::UnknownTable => e
  puts "Table not found: #{e.message}"
  puts "Error code: #{e.code}"
rescue ClickhouseRuby::ConnectionError => e
  puts "Connection failed: #{e.message}"
rescue ClickhouseRuby::QueryError => e
  puts "Query failed: #{e.message}"
  puts "SQL: #{e.sql}"
end
```

## Common Issues

| Error | Solution |
|-------|----------|
| `ConnectionError` | Check host/port, verify ClickHouse running |
| `UnknownTable` | CREATE TABLE before querying |
| `PoolTimeout` | Increase `pool_size` or reduce concurrency |
| `QueryTimeout` | Increase `read_timeout` or optimize query |
| `SyntaxError` | Check SQL syntax |
| `UnknownColumn` | Verify column exists in table |

## Type Mapping

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
| Enum8, Enum16 | String |
| Decimal(P,S) | BigDecimal |

## Performance Tips

1. **Use batch inserts** - Insert multiple rows at once
2. **Use streaming** - For queries returning millions of rows
3. **Enable compression** - For large payloads (>1KB)
4. **Use PREWHERE** - For query optimization (ActiveRecord)
5. **Use SAMPLE** - For approximate queries
6. **Tune pool size** - Based on concurrent requests
7. **Use EXPLAIN** - To analyze query performance

## See Also

- **[Getting Started](GETTING_STARTED.md)** - Step-by-step walkthrough
- **[Usage Guide](USAGE.md)** - Detailed usage examples
- **[Configuration Guide](CONFIGURATION.md)** - Complete configuration reference
- **[Production Guide](PRODUCTION_GUIDE.md)** - Production deployment
- **[Performance Tuning](PERFORMANCE_TUNING.md)** - Performance optimization
