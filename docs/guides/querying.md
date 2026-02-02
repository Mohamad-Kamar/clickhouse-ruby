# Querying Data

How to query data with ClickhouseRuby.

## Basic Queries

```ruby
require 'clickhouse_ruby'

client = ClickhouseRuby.client

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

## Result Object

The `Result` object provides rich metadata and access methods:

```ruby
result = client.execute('SELECT * FROM events LIMIT 100')

# Query execution metadata
result.elapsed_time    # => 0.042 (seconds)
result.rows_read       # => 100
result.bytes_read      # => 8500

# Result size
result.count           # => 100
result.size            # => 100

# Column information
result.columns         # => ["id", "event_type", "count"]
result.types           # => ["UInt64", "String", "UInt32"]

# Row access
result.first           # => {"id" => 1, "event_type" => "click", ...}
result.last            # => {"id" => 100, "event_type" => "view", ...}
result[5]              # => 6th row

# Get column values
result.column_values("event_type")  # => ["click", "view", ...]

# Enumerable methods
result.map { |row| row['count'] }
result.select { |row| row['count'] > 100 }
```

## Query Analysis (EXPLAIN)

Analyze query execution plans:

```ruby
# Default execution plan
plan = client.explain('SELECT * FROM events WHERE date = today()')

# Query pipeline (parallel stages)
pipeline = client.explain('SELECT * FROM events', type: :pipeline)

# Cost estimation
estimate = client.explain('SELECT count() FROM huge_table', type: :estimate)

# Abstract Syntax Tree
ast = client.explain('SELECT * FROM events', type: :ast)

# With settings
plan = client.explain(
  'SELECT * FROM events',
  type: :plan,
  settings: { max_threads: 4 }
)
```

**Explain Types:**
- `:plan` (default) - Execution plan with steps
- `:pipeline` - Parallel execution stages
- `:estimate` - Cost estimation
- `:ast` - Query structure
- `:syntax` - Parsed syntax

## Large Result Processing

### Batch Processing

Process results in batches for memory efficiency:

```ruby
client.each_batch('SELECT * FROM huge_table', batch_size: 500) do |batch|
  puts "Processing #{batch.size} rows"
  process_batch(batch)
end
```

### Row-by-Row Processing

Process one row at a time:

```ruby
client.each_row('SELECT * FROM massive_table') do |row|
  process_row(row)
end

# Or get an Enumerator
rows = client.each_row('SELECT * FROM table')
rows.each { |row| puts row['name'] }
```

### Streaming

For very large results, stream rows as they arrive:

```ruby
client.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
end
```

**Note:** Streaming cannot be used with FINAL or aggregate functions.

## DDL Commands

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

# Create database
client.command('CREATE DATABASE IF NOT EXISTS analytics')
```

## Module-Level API

Query without explicit client instance:

```ruby
result = ClickhouseRuby.execute('SELECT 1 AS num')
ClickhouseRuby.ping  # => true
```

## Performance Tips

1. **Use LIMIT** - Always limit results when possible
2. **Use streaming** - For queries returning millions of rows
3. **Use EXPLAIN** - Analyze slow queries
4. **Use PREWHERE** - Filter before reading columns (ActiveRecord)
5. **Use SAMPLE** - For approximate counts on large tables

## See Also

- **[Streaming Guide](streaming.md)** - Detailed streaming patterns
- **[Error Handling](error-handling.md)** - Handle query errors
- **[Reference: Query Extensions](../reference/query-extensions.md)** - PREWHERE, FINAL, SAMPLE
