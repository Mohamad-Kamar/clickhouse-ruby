# Inserting Data

How to insert data efficiently with ClickhouseRuby.

## Basic Inserts

```ruby
require 'clickhouse_ruby'

client = ClickhouseRuby.client

# Insert array of hashes (uses efficient JSONEachRow format)
client.insert('events', [
  { date: '2024-01-01', event_type: 'click', count: 100 },
  { date: '2024-01-02', event_type: 'view', count: 250 }
])
```

## Insert with Explicit Columns

```ruby
data = [
  { date: '2024-01-01', event_type: 'click', count: 100 },
  { date: '2024-01-02', event_type: 'view', count: 250 }
]

client.insert('events', data, columns: ['date', 'event_type', 'count'])
```

## Bulk Inserts

For large datasets, batch your inserts:

```ruby
# Generate large dataset
large_dataset = (1..10000).map do |i|
  { date: Date.today, event_type: 'event', count: i }
end

# Insert in one call
client.insert('events', large_dataset)
```

**Performance:** The `insert` method uses JSONEachRow format, which is ~5x faster than VALUES format.

## Insert with Settings

Configure insert behavior per-operation:

```ruby
# Async insert (returns immediately, processed later)
client.insert('events', records,
  settings: { async_insert: 1, wait_for_async_insert: 0 }
)

# With timeout
client.insert('events', records,
  settings: { insert_timeout: 300 }
)
```

## Chunked Inserts

For very large datasets, chunk the inserts:

```ruby
def insert_in_chunks(client, table, records, chunk_size: 10_000)
  records.each_slice(chunk_size) do |chunk|
    client.insert(table, chunk)
  end
end

# Usage
insert_in_chunks(client, 'events', million_records)
```

## Module-Level API

Insert without explicit client instance:

```ruby
ClickhouseRuby.insert('events', [
  { date: '2024-01-01', event_type: 'click' }
])
```

## ActiveRecord Inserts

With ActiveRecord integration:

```ruby
# Single record
Event.create(
  id: SecureRandom.uuid,
  event_type: 'click',
  created_at: Time.now
)

# Bulk insert (efficient)
Event.insert_all([
  { id: SecureRandom.uuid, event_type: 'click', created_at: Time.now },
  { id: SecureRandom.uuid, event_type: 'view', created_at: Time.now }
])
```

## Error Handling

```ruby
begin
  client.insert('events', records)
rescue ClickhouseRuby::QueryError => e
  puts "Insert failed: #{e.message}"
rescue ClickhouseRuby::ConnectionError => e
  puts "Connection failed: #{e.message}"
  # Consider retry logic
end
```

## Performance Tips

1. **Batch inserts** - Insert multiple rows at once (1000-10000 per call)
2. **Enable compression** - For large payloads (>1KB)
3. **Use async inserts** - For fire-and-forget scenarios
4. **Chunk large datasets** - Don't send millions of rows in one call
5. **Configure retries** - For transient failures

## Compression

Enable compression for large inserts:

```ruby
ClickhouseRuby.configure do |config|
  config.compression = 'gzip'
  config.compression_threshold = 1024  # Only compress > 1KB
end
```

## Retry Logic

Configure automatic retries:

```ruby
ClickhouseRuby.configure do |config|
  config.max_retries = 3
  config.initial_backoff = 1.0
  config.backoff_multiplier = 1.6
end
```

**Note:** INSERT is not idempotent - use `query_id` or `async_insert` for safe retries.

## See Also

- **[Configuration Guide](configuration.md)** - Configure compression and retries
- **[Error Handling](error-handling.md)** - Handle insert errors
- **[Production Guide](production.md)** - Production insert patterns
