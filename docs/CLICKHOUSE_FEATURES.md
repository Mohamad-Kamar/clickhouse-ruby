# ClickHouse-Specific Features

## Overview

This document details how ClickhouseRuby will support ClickHouse-specific features that differentiate it from traditional SQL databases.

## Table Engines

### MergeTree Family

The MergeTree family is the most important set of table engines in ClickHouse.

#### Basic MergeTree

```ruby
create_table :events, engine: 'MergeTree' do |t|
  t.datetime :event_time
  t.string :event_type
  t.uint64 :user_id
  t.string :data

  t.order_by :event_time, :user_id
  t.partition_by "toYYYYMM(event_time)"
end
```

**Generated SQL:**
```sql
CREATE TABLE events (
  event_time DateTime,
  event_type String,
  user_id UInt64,
  data String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, user_id)
```

#### ReplacingMergeTree

For deduplication based on ORDER BY columns:

```ruby
create_table :user_states, engine: 'ReplacingMergeTree' do |t|
  t.uint64 :user_id
  t.string :state
  t.datetime :updated_at

  t.order_by :user_id
  t.replacing_version :updated_at  # Optional version column
end
```

#### SummingMergeTree

For automatic summing of numeric columns:

```ruby
create_table :daily_stats, engine: 'SummingMergeTree' do |t|
  t.date :date
  t.string :category
  t.uint64 :views
  t.uint64 :clicks

  t.order_by :date, :category
  t.summing_columns :views, :clicks  # Columns to sum
end
```

#### AggregatingMergeTree

For storing pre-aggregated states:

```ruby
create_table :aggregated_stats, engine: 'AggregatingMergeTree' do |t|
  t.date :date
  t.string :category
  t.column :uniq_users, 'AggregateFunction(uniq, UInt64)'
  t.column :sum_amount, 'AggregateFunction(sum, Float64)'

  t.order_by :date, :category
end
```

#### CollapsingMergeTree

For handling state changes:

```ruby
create_table :sessions, engine: 'CollapsingMergeTree' do |t|
  t.uint64 :user_id
  t.datetime :start_time
  t.uint32 :duration
  t.int8 :sign  # Collapsing sign column

  t.order_by :user_id, :start_time
  t.collapsing_sign :sign
end
```

### Replicated Engines

For high availability and fault tolerance:

```ruby
create_table :events,
  engine: 'ReplicatedMergeTree',
  cluster: 'my_cluster',
  shard: '{shard}',
  replica: '{replica}' do |t|

  t.datetime :event_time
  t.string :event_type

  t.order_by :event_time
end
```

**Generated SQL:**
```sql
CREATE TABLE events ON CLUSTER my_cluster (
  event_time DateTime,
  event_type String
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}')
ORDER BY (event_time)
```

### Distributed Tables

For sharded clusters:

```ruby
create_distributed_table :events_distributed,
  cluster: 'my_cluster',
  database: 'default',
  local_table: 'events',
  sharding_key: 'rand()'
```

## Materialized Views

### Basic Materialized View

```ruby
create_materialized_view :hourly_stats do |v|
  v.select "toStartOfHour(event_time) AS hour, count() AS cnt"
  v.from :events
  v.group_by :hour
  v.to :hourly_stats_local  # Target table
end
```

### Aggregating Materialized View

```ruby
create_materialized_view :user_aggregates do |v|
  v.select <<-SQL
    user_id,
    uniqState(session_id) AS sessions,
    sumState(amount) AS total_amount
  SQL
  v.from :events
  v.group_by :user_id
  v.to :user_aggregates_store
  v.engine 'AggregatingMergeTree'
  v.order_by :user_id
end
```

### Refresh Management

```ruby
# Refresh materialized view data (requires ClickHouse 23.2+)
ClickhouseRuby.refresh_materialized_view(:hourly_stats)

# Check materialized view definition
view_info = ClickhouseRuby.materialized_view_info(:hourly_stats)
```

## TTL (Time-To-Live)

### Column-Level TTL

```ruby
create_table :logs do |t|
  t.datetime :timestamp
  t.string :message
  t.string :details, ttl: 'timestamp + INTERVAL 1 MONTH'  # Delete after 1 month

  t.order_by :timestamp
end
```

### Table-Level TTL

```ruby
create_table :logs,
  ttl: 'timestamp + INTERVAL 6 MONTH',
  ttl_action: 'DELETE' do |t|

  t.datetime :timestamp
  t.string :message

  t.order_by :timestamp
end
```

### Tiered Storage TTL

```ruby
create_table :logs,
  ttl: [
    { expr: 'timestamp + INTERVAL 1 DAY', to_disk: 'hot' },
    { expr: 'timestamp + INTERVAL 7 DAY', to_disk: 'warm' },
    { expr: 'timestamp + INTERVAL 30 DAY', to_disk: 'cold' },
    { expr: 'timestamp + INTERVAL 365 DAY', action: 'DELETE' }
  ] do |t|

  t.datetime :timestamp
  t.string :message

  t.order_by :timestamp
end
```

## SAMPLE Queries

For approximate queries on large datasets:

```ruby
# Sample 10% of data
Event.sample(0.1).count
# SELECT count() FROM events SAMPLE 0.1

# Sample with offset for reproducibility
Event.sample(0.1, offset: 123).count
# SELECT count() FROM events SAMPLE 0.1 OFFSET 123

# Sample N rows
Event.sample_rows(10000).count
# SELECT count() FROM events SAMPLE 10000
```

## Query Settings

### Query-Level Settings

```ruby
# Set settings for a single query
Event.settings(
  max_execution_time: 60,
  max_rows_to_read: 1_000_000
).where(date: Date.today).all
# SELECT * FROM events WHERE date = '2024-01-01' SETTINGS max_execution_time = 60, max_rows_to_read = 1000000

# Async insert settings
Event.settings(
  async_insert: 1,
  wait_for_async_insert: 0
).insert(records)
```

### Session-Level Settings

```ruby
ClickhouseRuby.configure do |config|
  config.default_settings = {
    max_threads: 4,
    max_memory_usage: 10_000_000_000
  }
end
```

### Common Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `max_execution_time` | Query timeout in seconds | `60` |
| `max_rows_to_read` | Limit rows scanned | `1_000_000` |
| `max_memory_usage` | Memory limit per query | `10_000_000_000` |
| `async_insert` | Enable async inserts | `1` |
| `wait_for_async_insert` | Wait for async completion | `0` |
| `insert_quorum` | Quorum for inserts | `2` |
| `select_sequential_consistency` | Read from replicas | `1` |
| `max_threads` | Parallel threads | `8` |
| `optimize_read_in_order` | Optimize ORDER BY | `1` |

## Mutations (UPDATE/DELETE)

### Understanding Mutations

ClickHouse mutations are **asynchronous** and **expensive**. They:
- Create new data parts
- Mark old parts as inactive
- Eventually merge and clean up

### DELETE Operations

```ruby
# Standard AR delete
Event.where(user_id: 123).delete_all
# ALTER TABLE events DELETE WHERE user_id = 123

# Check mutation status
ClickhouseRuby.mutation_status(:events)
# Returns: [{ mutation_id: '...', is_done: false, parts_to_do: 5 }]

# Wait for mutation completion
ClickhouseRuby.wait_for_mutations(:events, timeout: 300)
```

### UPDATE Operations

```ruby
# Standard AR update
Event.where(user_id: 123).update_all(status: 'inactive')
# ALTER TABLE events UPDATE status = 'inactive' WHERE user_id = 123

# Bulk update with expression
Event.where(user_id: 123).update_all("counter = counter + 1")
```

### Mutation Tracking

```ruby
# Get all pending mutations
mutations = ClickhouseRuby.pending_mutations(:events)

# Monitor mutation progress
ClickhouseRuby.on_mutation_complete(:events) do |mutation|
  puts "Mutation #{mutation.id} completed"
end
```

## PREWHERE Optimization

PREWHERE is executed before main WHERE, reading fewer columns:

```ruby
# Basic PREWHERE
Event.prewhere(active: true).where(user_id: 123)
# SELECT * FROM events PREWHERE active = 1 WHERE user_id = 123

# Chained conditions
Event.prewhere("date >= '2024-01-01'").where(category: 'sales')

# Complex PREWHERE
Event.prewhere(active: true, type: 'click').where("amount > 100")
```

### When to Use PREWHERE

Use PREWHERE for:
- Filtering columns with high selectivity
- Columns with good compression (reduces I/O)
- Simple boolean/enum conditions

WHERE is better for:
- Complex expressions
- Columns needed in SELECT anyway
- Low selectivity filters

## FINAL Modifier

For ReplacingMergeTree tables to get deduplicated results:

```ruby
# Get final (deduplicated) results
UserState.final.where(user_id: 123).first
# SELECT * FROM user_states FINAL WHERE user_id = 123 LIMIT 1

# Note: FINAL can be slow on large tables
```

## Array and Map Operations

### Array Functions

```ruby
# Array contains
Event.where("has(tags, 'important')")

# Array aggregation
Event.select("arrayJoin(tags) as tag").group(:tag).count

# Array transformation
Event.select("arrayMap(x -> x * 2, values) as doubled")
```

### Map Operations

```ruby
# Map access
Event.where("metadata['key'] = 'value'")

# Map keys/values
Event.select("mapKeys(metadata) as keys")
```

## Indexes

### Skip Indexes

```ruby
create_table :events do |t|
  t.datetime :timestamp
  t.string :message

  t.order_by :timestamp

  # Skip indexes for filtering
  t.index :message, type: 'tokenbf_v1', granularity: 4
  t.index :timestamp, type: 'minmax', granularity: 3
end
```

### Index Types

| Type | Use Case |
|------|----------|
| `minmax` | Range queries |
| `set(N)` | Equality on low-cardinality |
| `bloom_filter` | Membership testing |
| `tokenbf_v1` | Token search in strings |
| `ngrambf_v1` | Substring search |

## Projections

For optimizing specific query patterns:

```ruby
create_table :events do |t|
  t.datetime :timestamp
  t.string :user_id
  t.string :event_type
  t.float :amount

  t.order_by :timestamp, :user_id

  # Projection for user-based queries
  t.projection :by_user do |p|
    p.select :user_id, :timestamp, :event_type, :amount
    p.order_by :user_id, :timestamp
  end

  # Projection for aggregations
  t.projection :daily_totals do |p|
    p.select "toDate(timestamp) as date, sum(amount) as total"
    p.group_by "toDate(timestamp)"
  end
end
```

## Dictionary Support

```ruby
# Create dictionary
create_dictionary :country_names,
  source: { type: :clickhouse, table: :countries, key: :code, value: :name },
  layout: :flat,
  lifetime: { min: 300, max: 360 }

# Use in queries
Event.select("dictGet('country_names', 'name', country_code) as country_name")
```
