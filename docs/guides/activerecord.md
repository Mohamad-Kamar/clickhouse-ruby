# ActiveRecord Integration

## Overview
ClickhouseRuby includes an optional ActiveRecord adapter with full support for common ActiveRecord APIs, mapped to ClickHouse SQL with explicit error handling (no silent failures).

## Setup

Require the adapter and configure a ClickHouse connection. In Rails, add a `database.yml` entry; outside Rails, use `ActiveRecord::Base.establish_connection`.

```yaml
# config/database.yml
clickhouse:
  adapter: clickhouse
  host: localhost
  port: 8123
  database: analytics
  username: default
  password: ""
  ssl: false
  ssl_verify: true
  ssl_ca_path: "/path/to/ca.pem"
  pool: 5
  connect_timeout: 10
  read_timeout: 60
  write_timeout: 60
```

```ruby
# config/initializers/clickhouse.rb
require "clickhouse_ruby/active_record"

class ClickhouseRecord < ActiveRecord::Base
  self.abstract_class = true
  establish_connection :clickhouse
end
```

## Basic Queries

```ruby
class Event < ClickhouseRecord
  self.table_name = "events"
end

# SELECT queries
Event.where(event_type: "click").order(created_at: :desc).limit(10)
Event.where(user_id: 123).count

# INSERT
Event.insert_all([
  { id: SecureRandom.uuid, event_type: "click", created_at: Time.now },
  { id: SecureRandom.uuid, event_type: "view", created_at: Time.now }
])

# UPDATE mutations
Event.where(user_id: 123).update_all(status: "archived")

# DELETE mutations
Event.where(status: "old").delete_all
```

Notes:
- `update_all` / `delete_all` are translated to `ALTER TABLE ... UPDATE/DELETE` mutations
- Mutations are asynchronous in ClickHouse; the call returns once accepted
- ClickHouse does not return insert IDs; `insert_all` is recommended for bulk writes

## Schema and Migrations

The adapter implements `create_table`, `add_column`, `change_column`, `rename_column`, `add_index`, and related schema helpers. MergeTree tables require an engine and an `ORDER BY`.

### Migration Generator (v0.3.0+)

ClickhouseRuby provides a Rails generator for creating ClickHouse migrations with ClickHouse-specific options:

```bash
# Generate a migration
rails generate clickhouse:migration CreateEvents

# Generate with columns
rails generate clickhouse:migration CreateEvents user_id:integer name:string created_at:datetime

# Generate with ClickHouse options
rails generate clickhouse:migration CreateEvents \
  user_id:integer \
  name:string \
  --engine=ReplacingMergeTree \
  --order-by=user_id \
  --partition-by="toYYYYMM(created_at)" \
  --primary-key=user_id \
  --settings="index_granularity=8192"
```

**Generator Options:**

- `--engine` - ClickHouse table engine (default: `MergeTree`)
  - Valid engines: `MergeTree`, `ReplacingMergeTree`, `SummingMergeTree`, `AggregatingMergeTree`, `CollapsingMergeTree`, `VersionedCollapsingMergeTree`, `GraphiteMergeTree`, `Log`, `TinyLog`, `StripeLog`, `Memory`, `Null`, `Set`, `Join`, `Buffer`, `Distributed`, `MaterializedView`, `Dictionary`
- `--order-by` - ORDER BY clause for MergeTree family engines
- `--partition-by` - PARTITION BY clause for data partitioning
- `--primary-key` - PRIMARY KEY clause (defaults to ORDER BY if not specified)
- `--settings` - Table SETTINGS clause
- `--cluster` - Cluster name for distributed tables (automatically uses Replicated* engine)

**Examples:**

```bash
# Create table with ReplacingMergeTree
rails generate clickhouse:migration CreateUsers \
  id:uuid \
  email:string \
  status:string \
  --engine=ReplacingMergeTree \
  --order-by=id

# Create partitioned table
rails generate clickhouse:migration CreateEvents \
  id:uuid \
  event_type:string \
  created_at:datetime \
  --engine=MergeTree \
  --order-by="(event_type, created_at)" \
  --partition-by="toYYYYMM(created_at)"

# Create distributed table
rails generate clickhouse:migration CreateDistributedEvents \
  id:uuid \
  data:string \
  --engine=MergeTree \
  --order-by=id \
  --cluster=my_cluster

# Add column migration
rails generate clickhouse:migration AddStatusToUsers status:string

# Remove column migration
rails generate clickhouse:migration RemoveEmailFromUsers
```

The generator automatically detects migration type from the name:
- `Create*` → `create_table`
- `Add*To*` → `add_column`
- `Remove*From*` → `remove_column`
- Other names → `change_table`

### Manual Migrations

You can also create migrations manually:

```ruby
class CreateEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :events, engine: "MergeTree", order_by: "(event_type, created_at)",
                          partition_by: "toYYYYMM(created_at)" do |t|
      t.uuid :id, null: false
      t.string :event_type, null: false
      t.datetime :created_at, null: false
    end

    add_index :events, :event_type, type: "set", granularity: 1
  end
end
```

See [docs/ACTIVE_RECORD_SCHEMA.md](ACTIVE_RECORD_SCHEMA.md) for detailed migration patterns and options.

## Type Mapping

Common mappings:
- `string`/`text` → `String`
- `integer` → `Int32`
- `bigint` → `Int64`
- `float` → `Float32`/`Float64`
- `decimal` → `Decimal(p,s)`
- `datetime`/`timestamp` → `DateTime`/`DateTime64`
- `date` → `Date`
- `uuid` → `UUID`
- `json` → `String`

Note: `Array`, `Map`, and `Tuple` columns are treated as strings in ActiveRecord type casting.

## Query Extensions (v0.2.0+)

### PREWHERE - Query Optimization

Pre-filter rows before reading all columns (ClickHouse optimization):

```ruby
# Pre-filter on indexed column, then apply additional conditions
Event.prewhere(date: Date.today)
      .where(status: 'active')
      .count
# SELECT count() FROM events
# PREWHERE date = '2024-02-02'
# WHERE status = 'active'

# Works with ranges
Event.prewhere(created_at: 1.week.ago..)
     .where(user_id: [1, 2, 3])

# Works with negation
Event.prewhere.not(deleted: true)
     .where(status: 'active')
```

Use PREWHERE when:
- You have highly selective indexed columns
- You want to reduce column reads for large tables
- Requires MergeTree family tables

### FINAL - Deduplication

Return deduplicated results from ReplacingMergeTree or CollapsingMergeTree:

```ruby
# Get latest version of each row
User.final.where(id: 123)
# SELECT * FROM users FINAL WHERE id = 123

# With aggregation
User.final.group(:status).count
# SELECT status, count() FROM users FINAL GROUP BY status
```

Performance note: FINAL can be 2-10x slower (merges at query time). Use only when you need accuracy over speed.

### SAMPLE - Approximate Queries

Run queries on a sample of data for faster approximate results:

```ruby
# Fractional sampling (10% of data)
Event.sample(0.1).count
# SELECT count() FROM events SAMPLE 0.1

# Absolute row count (at least 10,000 rows)
Event.sample(10000).average(:amount)
# SELECT avg(amount) FROM events SAMPLE 10000

# With offset for reproducibility
Event.sample(0.1, offset: 0.5)
# SELECT * FROM events SAMPLE 0.1 OFFSET 0.5
```

Important:
- Integer 1 = "at least 1 row", Float 1.0 = "100% of data"
- `Event.sample(1)` = SAMPLE 1 (absolute)
- `Event.sample(1.0)` = SAMPLE 1.0 (fractional = 100%)
- Requires table created with `SAMPLE BY` clause
- Results are approximate (use with caution for exact counts)

### SETTINGS - Query Configuration

Add ClickHouse settings to individual queries:

```ruby
# Increase thread parallelism
Event.settings(max_threads: 4).where(active: true).count
# SELECT count() FROM events WHERE active = 1 SETTINGS max_threads = 4

# Multiple settings
Event.settings(max_threads: 4, async_insert: true)
# SELECT * FROM events SETTINGS max_threads = 4, async_insert = 1

# Boolean normalization (true → 1, false → 0)
Event.settings(final: true)
# SELECT * FROM events SETTINGS final = 1

# Chaining with other methods
Event.where(active: true)
     .settings(max_rows_to_read: 1000000)
     .limit(100)
```

### Combining Features

```ruby
# Complex query with all Phase 2.0 features
User.final
    .prewhere(created_at: 1.week.ago..)
    .where(status: 'active')
    .sample(0.1)
    .settings(max_threads: 4)
    .order(id: :desc)
    .limit(100)

# Generates:
# SELECT * FROM users FINAL
# SAMPLE 0.1
# PREWHERE created_at >= '2026-01-26'
# WHERE status = 'active'
# ORDER BY id DESC
# LIMIT 100
# SETTINGS max_threads = 4
```

Note: FINAL + PREWHERE automatically adds optimization settings.

## Type Features (v0.2.0+)

### Enum Type

Fixed set of predefined values with automatic string-to-integer mapping:

```ruby
# Define model
class Status < ClickhouseRecord
  self.table_name = "statuses"
end

# Table schema
CREATE TABLE statuses (
  id UUID,
  status Enum8('active' = 1, 'inactive' = 2, 'archived' = 3)
)

# Usage - automatically maps string to enum value
Status.create(id: SecureRandom.uuid, status: 'active')
Status.where(status: 'active').count
```

### Decimal Type

Arbitrary precision arithmetic for financial data:

```ruby
class Price < ClickhouseRecord
  self.table_name = "prices"
end

# Table schema
CREATE TABLE prices (
  id UUID,
  product_id UUID,
  amount Decimal(18, 4),
  currency String
)

# Usage - uses BigDecimal for precision
Price.create(
  id: SecureRandom.uuid,
  product_id: prod_id,
  amount: BigDecimal('99.9999'),
  currency: 'USD'
)

# Query
Price.where(currency: 'USD').sum(:amount)
```

Important: Always use `BigDecimal` in Ruby, NOT `Float`. Decimal auto-maps to Decimal32/64/128/256 based on precision.

## Client Features (v0.2.0+)

### Result Streaming

Process large results with constant memory usage:

```ruby
# Stream processing large tables
Event.find_each_row(batch_size: 1000) { |row| process(row) }

# Or use the client directly
client.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
end
```

### HTTP Compression

Automatic gzip compression for large payloads:

```ruby
# Configure in initializer
ClickhouseRuby.configure do |config|
  config.compression = 'gzip'
  config.compression_threshold = 1024
end
```

### Retry Logic

Automatic retries with exponential backoff:

```ruby
ClickhouseRuby.configure do |config|
  config.max_retries = 3
  config.initial_backoff = 1.0
  config.backoff_multiplier = 1.6
  config.max_backoff = 120
  config.retry_jitter = :equal
end
```

Auto-retries on:
- Connection errors
- Timeout errors
- HTTP 5xx errors
- HTTP 429 (rate limit)

Does NOT retry on:
- QueryError (syntax errors)
- HTTP 4xx errors (client errors)

## Limitations

- No transactions, savepoints, or rollback
- No foreign keys, check constraints, insert returning, comments, partial/expression indexes, or standard views
- No auto-increment primary keys; generate IDs in your application

## Rails Database Tasks

When used in Rails, the adapter plugs into `db:create`, `db:drop`, and `db:purge`. It also supports structure dump/load via `db:structure:dump` and `db:structure:load` (ClickHouse `SHOW CREATE TABLE`).
