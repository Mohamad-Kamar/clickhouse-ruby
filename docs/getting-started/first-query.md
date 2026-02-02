# Your First Query

Learn to create tables, insert data, and run queries with ClickhouseRuby.

## Prerequisites

- ClickhouseRuby installed ([Installation Guide](installation.md))
- ClickHouse running

## Create a Table

```ruby
require 'clickhouse_ruby'

client = ClickhouseRuby.client

# Create a database (optional)
client.command('CREATE DATABASE IF NOT EXISTS analytics')

# Create a table
client.command(<<~SQL)
  CREATE TABLE analytics.events (
    id UUID,
    event_type String,
    user_id UInt64,
    created_at DateTime,
    properties String
  ) ENGINE = MergeTree()
  ORDER BY (event_type, created_at)
SQL
```

**Note:** ClickHouse requires an `ORDER BY` clause for MergeTree tables. This determines how data is sorted and indexed.

## Insert Data

```ruby
require 'securerandom'

events = [
  {
    id: SecureRandom.uuid,
    event_type: 'page_view',
    user_id: 12345,
    created_at: Time.now,
    properties: '{"page": "/home"}'
  },
  {
    id: SecureRandom.uuid,
    event_type: 'click',
    user_id: 12345,
    created_at: Time.now,
    properties: '{"button": "signup"}'
  }
]

client.insert('analytics.events', events)
```

ClickhouseRuby uses JSONEachRow format for inserts, which is ~5x faster than VALUES syntax.

## Query Data

### Simple Query

```ruby
result = client.execute('SELECT * FROM analytics.events LIMIT 10')

result.each do |row|
  puts "#{row['event_type']} by user #{row['user_id']}"
end
```

### Count Records

```ruby
result = client.execute('SELECT count() FROM analytics.events')
puts "Total events: #{result.first['count()']}"
```

### Aggregations

```ruby
result = client.execute(<<~SQL)
  SELECT
    event_type,
    count() as count,
    uniq(user_id) as unique_users
  FROM analytics.events
  GROUP BY event_type
SQL

result.each do |row|
  puts "#{row['event_type']}: #{row['count']} events, #{row['unique_users']} users"
end
```

### Access Result Metadata

```ruby
result = client.execute('SELECT * FROM analytics.events')

# Column info
result.columns      # => ['id', 'event_type', 'user_id', ...]
result.types        # => ['UUID', 'String', 'UInt64', ...]

# Query stats (v0.3.0+)
result.elapsed_time # => 0.042 (seconds)
result.rows_read    # => 100
result.bytes_read   # => 8500
```

## Handle Errors

```ruby
begin
  client.execute('SELECT * FROM nonexistent_table')
rescue ClickhouseRuby::UnknownTable => e
  puts "Table not found: #{e.message}"
rescue ClickhouseRuby::ConnectionError => e
  puts "Connection failed: #{e.message}"
end
```

## Process Large Results

For large datasets, use streaming to avoid memory issues:

```ruby
# Stream row by row (constant memory)
client.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
end

# Process in batches
client.each_batch('SELECT * FROM huge_table', batch_size: 1000) do |batch|
  process_batch(batch)
end
```

## Clean Up

```ruby
# Drop the table when done experimenting
client.command('DROP TABLE IF EXISTS analytics.events')
```

## Next Steps

- **[Rails Quickstart](rails-quickstart.md)** - Use with Rails/ActiveRecord
- **[Querying Guide](../guides/querying.md)** - Advanced query patterns
- **[Inserting Guide](../guides/inserting.md)** - Bulk inserts and performance
