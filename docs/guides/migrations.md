# ActiveRecord Schema Operations & Introspection

## Overview

This guide documents ActiveRecord schema operations for ClickhouseRuby, focusing on database
management, table creation, introspection, and engine-specific features. This complements
[ACTIVE_RECORD.md](./ACTIVE_RECORD.md), which covers query operations and basic schema setup.

**Important:** ClickHouse schema operations differ significantly from traditional SQL databases:
- **No rollbacks**: DDL changes are immediate and irreversible
- **Eventual consistency**: Cluster operations may not be instantly consistent
- **Metadata-driven**: Many operations only modify metadata, not data
- **Engine selection**: Critical decision that can't easily be changed later

This guide emphasizes production-ready patterns, safety practices, and ClickHouse-specific
considerations. Always test migrations on realistic data volumes before production deployment.

## Table of Contents

1. [Database Management](#database-management)
2. [View Operations](#view-operations)
3. [Schema Introspection](#schema-introspection)
4. [Table Metadata](#table-metadata)
5. [Migration Patterns](#migration-patterns)
6. [Engine-Specific Schema](#engine-specific-schema)
7. [Related Operations](#related-operations)
8. [Performance Tuning](#performance-tuning)
9. [Best Practices](#best-practices)
10. [Integration with Rails](#integration-with-rails)

---

## Database Management

### Listing Databases

Use the ActiveRecord connection adapter to list all databases in your ClickHouse cluster:

```ruby
# In a migration or controller
databases = ActiveRecord::Base.connection.databases
# => ["default", "analytics", "events", "system"]

databases.each do |db|
  puts "Database: #{db}"
end
```

The `.databases` method queries the `system.databases` table and returns database names as
strings. The `system` database is always present and contains metadata tables.

### Creating Databases

Create a new database in a migration:

```ruby
class CreateAnalyticsDatabase < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE DATABASE IF NOT EXISTS analytics
      ENGINE = Ordinary
    SQL
  end

  def down
    # Always test rollback strategy in ClickHouse (no automatic rollback support)
    execute "DROP DATABASE IF EXISTS analytics"
  end
end
```

Database engine options:

```ruby
# Ordinary engine (default, metadata on local filesystem)
execute "CREATE DATABASE ordinary_db ENGINE = Ordinary"

# Atomic engine (transactional, metadata in Zk, recommended for Replicated tables)
execute "CREATE DATABASE atomic_db ENGINE = Atomic"

# Replicated engine (for distributed clusters with ZooKeeper)
execute "CREATE DATABASE replicated_db ENGINE = Replicated('/clickhouse/db/replicated', 'shard1', 'replica1')"
```

**Atomic engine recommendation:** Use `Atomic` for production clusters with replication, as it
provides atomic DDL and better coordination with ZooKeeper.

### Switching and Current Database

In Rails `config/database.yml`:

```yaml
development:
  adapter: clickhouse
  url: http://localhost:8123/events
  username: default
  password:

production:
  adapter: clickhouse
  url: http://production-ch-node:8123/analytics
  username: clickhouse_user
  password: <%= ENV['CLICKHOUSE_PASSWORD'] %>
```

In models, specify database explicitly:

```ruby
class Event < ApplicationRecord
  self.table_name = "events.raw_events"

  establish_connection :analytics  # Use 'analytics' connection config
end

class User < ApplicationRecord
  # Uses default connection (events database from URL)
  self.table_name = "users"
end
```

Query current database:

```ruby
current_db = ActiveRecord::Base.connection.execute(
  "SELECT currentDatabase() as db"
).first
# => {"db" => "events"}
```

### Dropping Databases Safely

**Warning:** Dropping a database is permanent and cannot be rolled back. Always verify before
executing.

```ruby
class DropTestDatabase < ActiveRecord::Migration[6.0]
  def up
    # Confirm this isn't production
    raise "Cannot drop database in production!" if Rails.env.production?

    execute "DROP DATABASE IF EXISTS test_db"
  end
end
```

Dropping with cluster propagation:

```ruby
execute "DROP DATABASE IF EXISTS old_db ON CLUSTER 'default'"
```

### Replication Considerations

When using replicated databases, consider the cluster setup:

```ruby
# Multi-node setup with 2 shards, 2 replicas each
class CreateReplicatedDatabase < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE DATABASE IF NOT EXISTS distributed_db
      ENGINE = Replicated(
        '/clickhouse/databases/distributed_db',
        'shard_{shard}',
        'replica_{replica}'
      )
    SQL
  end
end
```

ZooKeeper paths follow the pattern: `/clickhouse/databases/name/shard_N/replica_M`

All replicas of a database must have the same tables and structure. Use `ON CLUSTER` clauses
in all DDL statements to propagate changes across the cluster.

### System vs User Databases

ClickHouse reserves certain databases for system metadata:

- `system`: Read-only metadata tables (tables, columns, merges, partitions, etc.)
- `information_schema`: SQL standard information schema views
- `default`: Created automatically for unqualified table references

Avoid creating tables in `system` or `information_schema`. Always work with explicitly
named user databases.

### Permissions Model

ClickHouse uses username and quota-based permissions:

```ruby
# Connect with specific user and quota
ClickhouseRuby.configure do |config|
  config.username = "analytics_user"
  config.password = ENV['CLICKHOUSE_PASSWORD']
end

# Query current user
user = ActiveRecord::Base.connection.execute("SELECT currentUser() as user").first
# => {"user" => "analytics_user"}
```

### Gotchas

**No Default User Database:** Unlike PostgreSQL, there's no automatic user database. Create
named databases explicitly.

**Non-Rollback Operations:** All DDL is immediate. Test migrations thoroughly on production-like
data before running them.

**Cluster Complexity:** Replicated setups require careful ZooKeeper coordination. Single-node
deployments are simpler for development.

---

## View Operations

Views in ClickHouse provide read-only abstraction over tables. Three types exist:
**Regular Views** (query shortcuts), **Materialized Views** (stored results), and **Live Views**
(real-time aggregations).

### Listing Views

```ruby
# List all views in current database
views = ActiveRecord::Base.connection.views
# => ["daily_events_summary", "user_by_country", "realtime_metrics"]

# List views from system.views
view_names = ActiveRecord::Base.connection.execute(
  "SELECT name FROM system.views WHERE database = currentDatabase()"
).map { |row| row["name"] }
```

### Checking View Existence

```ruby
if ActiveRecord::Base.connection.view_exists?("daily_events_summary")
  puts "View already exists"
else
  puts "Create view first"
end
```

### Creating Regular Views

Regular views are read-only shortcuts to SELECT queries. They don't store data:

```ruby
class CreateEventSummaryView < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE VIEW event_summary AS
      SELECT
        event_type,
        toDate(timestamp) as date,
        count() as count,
        countDistinct(user_id) as unique_users
      FROM raw_events
      GROUP BY event_type, date
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS event_summary"
  end
end
```

Use regular views for commonly-run aggregations, metric calculations, or to simplify JOIN logic.

### Creating Materialized Views

Materialized views store the query results in a hidden table and automatically populate as new
data arrives:

```ruby
class CreateDailyMetricsMaterialized < ActiveRecord::Migration[6.0]
  def up
    # Target table: stores aggregated results
    execute <<~SQL
      CREATE TABLE IF NOT EXISTS daily_metrics (
        date Date,
        metric_type String,
        count UInt64,
        sum_value Float64
      ) ENGINE = SummingMergeTree()
      PRIMARY KEY (date, metric_type)
    SQL

    # Materialized view: automatically populates target table
    execute <<~SQL
      CREATE MATERIALIZED VIEW IF NOT EXISTS daily_metrics_mv
      TO daily_metrics AS
      SELECT
        toDate(timestamp) as date,
        metric_type,
        count() as count,
        sum(value) as sum_value
      FROM raw_metrics
      GROUP BY date, metric_type
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS daily_metrics_mv"
    execute "DROP TABLE IF EXISTS daily_metrics"
  end
end
```

**Key difference:** Materialized views require a target table. Data flows automatically:
`raw_metrics` → aggregation → `daily_metrics` table.

### Creating Live Views

Live views compute aggregates in real-time using special memory structures:

```ruby
class CreateLiveRealtimeMetrics < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE LIVE VIEW IF NOT EXISTS realtime_metrics AS
      SELECT
        event_type,
        count() as count
      FROM raw_events
      GROUP BY event_type
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS realtime_metrics"
  end
end
```

Query a live view (results update as data arrives):

```ruby
# Only works with WATCH command in client, not standard SELECT
# Live views are specialized for real-time dashboards and streaming aggregates
```

**Note:** Live views are advanced and rarely used in Rails applications. Use materialized views
for production workloads.

### Dropping Views

```ruby
execute "DROP VIEW IF EXISTS event_summary"

# With clustering
execute "DROP VIEW IF EXISTS event_summary ON CLUSTER 'default'"
```

### View Performance Trade-offs

| Type | Storage | Speed | Auto-Update | Use Case |
|------|---------|-------|------------|----------|
| Regular | None (query only) | Slow (computed per query) | N/A | Complex logic shortcuts |
| Materialized | Stored table | Fast (pre-aggregated) | Yes, automatic | Dashboards, metrics |
| Live | Memory | Real-time | Yes, streaming | Real-time monitoring |

For production dashboards, materialized views provide the best balance of performance and
automatic updates. Regular views are cheap for one-off queries. Live views are specialized.

### Updating Materialized Views

Materialized views automatically populate as new data arrives, but historical data requires
manual refresh:

```ruby
class RefreshDailyMetricsJob < ApplicationJob
  def perform
    # Clear and rebuild for date range
    connection = ActiveRecord::Base.connection
    
    # Truncate target table
    connection.execute("TRUNCATE TABLE daily_metrics")
    
    # Re-insert from raw data
    connection.execute(<<~SQL)
      INSERT INTO daily_metrics
      SELECT
        toDate(timestamp) as date,
        metric_type,
        count() as count,
        sum(value) as sum_value
      FROM raw_metrics
      GROUP BY date, metric_type
    SQL
  end
end
```

Schedule periodic refreshes to catch data corrections or late-arriving data.

### View Dependencies and Schema Evolution

When renaming or altering source tables, dependent views break:

```ruby
# Source table
CREATE TABLE events (id UInt32, timestamp DateTime) ENGINE = MergeTree();

# View depending on it
CREATE VIEW events_summary AS SELECT count() FROM events;

# Rename table (breaks view!)
ALTER TABLE events RENAME TO raw_events;
# View still references 'events' (now invalid)

# Solution: recreate view with updated reference
CREATE OR REPLACE VIEW events_summary AS SELECT count() FROM raw_events;
```

**Best practice:** Track view dependencies. When modifying schema, update dependent views.

### Gotchas

**Can't Index Views:** Only tables support indexes. Create proper indexes on underlying tables
before creating views.

**Separate Tables for Materialization:** The target table of a materialized view is separate from
the view itself. Delete view but keep table for data persistence.

**No Auto-Refresh:** Materialized views don't auto-refresh historical data. Manual refresh required
for late-arriving corrections.

---

## Schema Introspection

### Listing Tables

```ruby
# Get all tables in current database
tables = ActiveRecord::Base.connection.tables
# => ["users", "events", "metrics"]

# Get tables from specific database
tables = ActiveRecord::Base.connection.execute(
  "SELECT name FROM system.tables WHERE database = 'analytics'"
).map { |row| row["name"] }
```

### Listing Columns

```ruby
# Get columns for a table
columns = ActiveRecord::Base.connection.columns("users")
# => [#<ActiveRecord::ConnectionAdapters::Column name="id" type=:integer>,
#     #<ActiveRecord::ConnectionAdapters::Column name="email" type=:string>,
#     #<ActiveRecord::ConnectionAdapters::Column name="created_at" type=:datetime>]

columns.each do |col|
  puts "#{col.name} (#{col.type})"
end
```

### Checking Column Existence

```ruby
if ActiveRecord::Base.connection.column_exists?("users", "email")
  puts "Email column exists"
else
  puts "Add email column first"
end

# In migration
unless column_exists?(:users, :phone_number)
  add_column :users, :phone_number, :string
end
```

### Primary Keys

```ruby
# Get primary key for table
primary_key = ActiveRecord::Base.connection.primary_keys("users")
# => ["id"]

# In system.tables
pks = ActiveRecord::Base.connection.execute(<<~SQL).map { |r| r["primary_key"] }
  SELECT primary_key FROM system.tables WHERE name = 'users'
SQL
```

**Important:** In ClickHouse, primary keys are NOT unique constraints. They're used for
data organization and query optimization, but duplicates are allowed.

### Indexes

ClickHouse uses data-skipping indexes (not traditional B-tree indexes):

```ruby
# List indexes on table
indexes = ActiveRecord::Base.connection.indexes("events")
# => [#<ActiveRecord::ConnectionAdapters::IndexDefinition name="idx_event_type_date" ...>]

# Check index existence
if ActiveRecord::Base.connection.index_exists?("events", "event_type")
  puts "Index exists"
end

# Query system.indexes for detailed information
index_info = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    name,
    type,
    expr,
    granularity
  FROM system.indexes
  WHERE table = 'events'
SQL
```

### Column Metadata

```ruby
# Detailed column information from system.columns
col_info = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    name,
    type,
    default_expression,
    default_kind,
    comment
  FROM system.columns
  WHERE table = 'users' AND database = currentDatabase()
SQL

col_info.each do |col|
  puts "#{col['name']}: #{col['type']}"
  puts "  Default: #{col['default_expression']} (#{col['default_kind']})"
  puts "  Comment: #{col['comment']}"
end
```

Column metadata fields:
- `default_kind`: "DEFAULT", "MATERIALIZED", or empty
- `default_expression`: Expression for computed columns
- `comment`: User-added column documentation

### Querying System Tables Directly

For advanced introspection, query `system.tables` and `system.columns` directly:

```ruby
# Table structure and engine info
table_info = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    name,
    engine,
    total_rows,
    total_bytes,
    create_table_query
  FROM system.tables
  WHERE database = currentDatabase()
  ORDER BY total_bytes DESC
SQL

# All columns with nullability
columns = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    name,
    type,
    is_in_primary_key,
    is_in_sorting_key,
    comment
  FROM system.columns
  WHERE database = currentDatabase()
  AND table = 'events'
SQL
```

### Schema Dumper Limitations

Rails' `schema.rb` dumper has limited support for ClickHouse. Custom engines and options may
not serialize correctly:

```ruby
# Generate schema dump (basic support)
rake db:schema:dump
# Produces: db/schema.rb

# Limitations:
# - Engine options may be incomplete
# - Partition keys not fully captured
# - TTL settings not preserved
# - Index granularity settings lost

# Workaround: Store schema as SQL files
execute "SELECT create_table_query FROM system.tables WHERE name = 'events'" do |row|
  File.write("db/clickhouse_schema/#{row['name']}.sql", row['create_table_query'])
end
```

### ClickHouse Differences from SQL

| Feature | Traditional SQL | ClickHouse |
|---------|-----------------|-----------|
| Primary Key | UNIQUE constraint | Query optimization, allows duplicates |
| Indexes | B-tree, hash | Data-skipping (minmax, set, bloom_filter) |
| Foreign Keys | Enforced referential integrity | No support |
| Transactions | ACID transactions | Limited: single mutation atomic |
| Constraints | CHECK, UNIQUE, NOT NULL | No support |

ClickHouse prioritizes query performance over data integrity constraints. Enforce business logic
in application code.

### Gotchas

**Primary Keys Aren't Unique:** Multiple rows can have the same primary key. Use FINAL with
ReplacingMergeTree for deduplication.

**Indexes Are Hints:** Data-skipping indexes help ClickHouse skip partitions, but don't guarantee
query performance like traditional indexes.

**Metadata Variations:** Different ClickHouse versions may report different metadata fields.
Handle missing fields gracefully.

---

## Table Metadata

### Querying System Tables for Metadata

```ruby
# Comprehensive table metadata
metadata = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    name as table_name,
    engine,
    partition_key,
    primary_key,
    sorting_key,
    total_rows,
    total_bytes,
    data_uncompressed_bytes,
    data_compressed_bytes,
    creation_time,
    lifetime_rows,
    lifetime_bytes
  FROM system.tables
  WHERE database = currentDatabase()
  ORDER BY total_bytes DESC
SQL
```

### Engine Information and Selection

ClickHouse provides specialized engines for different workloads:

```ruby
# List all available engines and their usage
engines = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    name,
    total_rows,
    total_bytes
  FROM system.tables
  WHERE database = currentDatabase()
  GROUP BY engine
SQL

engines.each do |e|
  puts "#{e['name']}: #{e['total_rows']} rows, #{e['total_bytes']} bytes"
end
```

### Partition Structure and Pruning

```ruby
# Partition information for a table
partitions = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    partition,
    name,
    rows,
    bytes_on_disk,
    modification_time
  FROM system.parts
  WHERE database = currentDatabase()
  AND table = 'events'
  ORDER BY modification_time DESC
SQL

partitions.each do |p|
  puts "Partition: #{p['partition']} - #{p['rows']} rows, #{p['bytes_on_disk']} bytes"
end
```

Partitions allow ClickHouse to skip reading entire date ranges during queries.

### ORDER BY and PRIMARY KEY Effects

```ruby
# Query PRIMARY KEY and ORDER BY settings
key_info = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    name,
    primary_key,
    order_by
  FROM system.tables
  WHERE name = 'events'
SQL

# Primary key affects query performance and merges
# ORDER BY determines physical storage order
```

Proper PRIMARY KEY and ORDER BY selection dramatically impacts query performance.

### Replication Status and Lag

```ruby
# Replication lag for Replicated tables
replica_status = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    database,
    table,
    is_leader,
    absolute_delay
  FROM system.replicas
SQL

replica_status.each do |r|
  delay = r['absolute_delay'] > 0 ? "#{r['absolute_delay']} rows behind" : "In sync"
  leader = r['is_leader'] ? "Leader" : "Follower"
  puts "#{r['database']}.#{r['table']}: #{leader} - #{delay}"
end
```

### Compression Information

```ruby
# Analyze compression ratios
compression = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    table,
    data_compressed_bytes,
    data_uncompressed_bytes,
    ROUND(100.0 * (1 - CAST(data_compressed_bytes AS Float64) /
          data_uncompressed_bytes), 2) AS compression_ratio_percent
  FROM system.tables
  WHERE database = currentDatabase()
  ORDER BY compression_ratio_percent DESC
SQL
```

### TTL (Time-To-Live) Expressions

```ruby
# Query TTL settings
ttl_info = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    name,
    ttl_expression
  FROM system.tables
  WHERE database = currentDatabase()
  AND ttl_expression != ''
SQL

# TTL automatically deletes old rows or moves to cold storage
```

### Row Count Estimation (Approximate)

```ruby
# Approximate row counts (fast, not exact)
approx_counts = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    table,
    total_rows as exact_rows
  FROM system.tables
  WHERE database = currentDatabase()
SQL

# For exact counts, use: SELECT count(*) FROM table (slower)
```

### Storage Analysis and Efficiency

```ruby
# Storage efficiency report
efficiency = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    table,
    total_bytes / 1024 / 1024 as size_mb,
    total_rows,
    ROUND(total_bytes / total_rows, 2) as bytes_per_row,
    engine
  FROM system.tables
  WHERE database = currentDatabase()
  ORDER BY total_bytes DESC
  LIMIT 10
SQL

efficiency.each do |row|
  puts "#{row['table']} (#{row['engine']}): #{row['size_mb']}MB, #{row['bytes_per_row']} bytes/row"
end
```

### Gotchas

**Approximate Counts:** `total_rows` in `system.tables` is approximate. Use `SELECT count(*)` for
exact counts (slower on large tables).

**Storage Doesn't Include Replicas:** `total_bytes` only counts local storage, not replicated
copies.

**Compression Varies:** Compression ratios depend on data patterns. Some columns compress 10:1,
others 1.5:1.

---

## Migration Patterns

### ClickHouse vs Traditional Migrations

ClickHouse differs from SQL migrations fundamentally:

| Aspect | Traditional SQL | ClickHouse |
|--------|-----------------|-----------|
| Rollback | Supported via transaction | **No rollback** - immediate and final |
| Execution | Within transaction | Immediate, metadata-only where possible |
| Large tables | ALTER locks table | ALTER on existing tables is metadata-only |
| Testing | Can rollback test runs | Must test on copy/staging cluster |

**Critical:** Test all migrations thoroughly on production-like data before execution. There's no
rollback.

### Adding Columns (Metadata-Only)

For MergeTree tables, adding columns is fast (metadata-only):

```ruby
class AddPhoneToUsers < ActiveRecord::Migration[6.0]
  def up
    execute "ALTER TABLE users ADD COLUMN phone_number String"
  end

  def down
    execute "ALTER TABLE users DROP COLUMN phone_number"
  end
end
```

New rows get the default value. Existing rows return NULL for the new column (no data rewrite).

### Adding Columns Safely (Nullable for Backfill)

For production tables, add nullable columns first, then backfill:

```ruby
class AddRequiredFieldSafely < ActiveRecord::Migration[6.0]
  def up
    # Step 1: Add nullable
    execute "ALTER TABLE events ADD COLUMN category Nullable(String)"
    
    # Step 2: Backfill in background job (see below)
    # BackfillEventsJob.perform_later
  end

  def down
    execute "ALTER TABLE events DROP COLUMN category"
  end
end

# Background job for gradual backfill
class BackfillEventsJob < ApplicationJob
  queue_as :default

  def perform
    Event.find_in_batches(batch_size: 1_000_000) do |batch|
      ids = batch.map(&:id)
      ActiveRecord::Base.connection.execute(<<~SQL)
        ALTER TABLE events UPDATE category = 'default'
        WHERE id IN (#{ids.join(',')}) AND category IS NULL
      SQL
    end
  end
end
```

**Caveat:** ClickHouse mutations (UPDATE/DELETE) are slower than inserts. For massive backfills,
consider recreating the table with the new structure.

### Removing Columns (Actual Data Deletion)

Dropping columns removes data, so test carefully:

```ruby
class RemoveDeprecatedColumn < ActiveRecord::Migration[6.0]
  def up
    execute "ALTER TABLE events DROP COLUMN old_field"
  end

  def down
    # Recreate column (data is lost, migration is irreversible)
    execute "ALTER TABLE events ADD COLUMN old_field String"
  end
end
```

On large tables, this operation is expensive. Plan removal during low-traffic windows.

### Renaming Columns (Metadata Only)

```ruby
class RenameEventTypeToCategory < ActiveRecord::Migration[6.0]
  def up
    execute "ALTER TABLE events RENAME COLUMN event_type TO category"
  end

  def down
    execute "ALTER TABLE events RENAME COLUMN category TO event_type"
  end
end
```

Renaming is metadata-only and fast. However, any dependent views or queries must be updated.

### Modifying Column Types (Requires Data Migration)

Changing types requires recreating the table:

```ruby
class ChangeEventIdType < ActiveRecord::Migration[6.0]
  def up
    # Create new table with updated schema
    execute <<~SQL
      CREATE TABLE events_new (
        id UInt64,
        name String,
        timestamp DateTime
      ) ENGINE = MergeTree()
      PRIMARY KEY (id, timestamp)
      ORDER BY (id, timestamp)
    SQL

    # Copy data
    execute "INSERT INTO events_new SELECT * FROM events"

    # Swap tables
    execute "RENAME TABLE events TO events_old"
    execute "RENAME TABLE events_new TO events"

    # Drop old table
    execute "DROP TABLE events_old"
  end

  def down
    # Reverse is complex; recommend testing extensively before running
    raise "Cannot rollback type change; recreate from backup"
  end
end
```

**Warning:** On large tables (>1GB), this operation takes significant time and disk space.

### Managing Indexes (Data Skipping)

ClickHouse indexes are data-skipping, not traditional:

```ruby
class AddIndexesForQueryOptimization < ActiveRecord::Migration[6.0]
  def up
    # minmax index (useful for range queries)
    execute "ALTER TABLE events ADD INDEX idx_timestamp_minmax timestamp TYPE minmax GRANULARITY 1"

    # set index (useful for IN/equality)
    execute "ALTER TABLE events ADD INDEX idx_status_set status TYPE set(100) GRANULARITY 1"

    # bloom_filter index (probabilistic set membership)
    execute "ALTER TABLE events ADD INDEX idx_user_id_bloom user_id TYPE bloom_filter GRANULARITY 1"
  end

  def down
    execute "ALTER TABLE events DROP INDEX idx_timestamp_minmax"
    execute "ALTER TABLE events DROP INDEX idx_status_set"
    execute "ALTER TABLE events DROP INDEX idx_user_id_bloom"
  end
end
```

### Partitioning Strategies and Changes

```ruby
# Create partitioned table
class CreatePartitionedEvents < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE events_partitioned (
        event_type String,
        timestamp DateTime,
        user_id UInt32
      ) ENGINE = MergeTree()
      PARTITION BY toYYYYMM(timestamp)
      PRIMARY KEY (event_type, timestamp)
      ORDER BY (event_type, timestamp)
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS events_partitioned"
  end
end

# Repartition existing table (recreate)
class RepartitionEventsDaily < ActiveRecord::Migration[6.0]
  def up
    execute "CREATE TABLE events_daily AS events"
    
    execute <<~SQL
      ALTER TABLE events_daily
      MODIFY PARTITION BY toYYYYMMDD(timestamp)
    SQL
    # Note: Actual repartitioning requires table recreation
  end
end
```

### Engine Changes (Require Recreation)

Changing table engine requires full recreation:

```ruby
class MigrateFromSummingToRegularMergeTree < ActiveRecord::Migration[6.0]
  def up
    # Back up existing
    execute "RENAME TABLE metrics TO metrics_summing"

    # Create new table with different engine
    execute <<~SQL
      CREATE TABLE metrics (
        date Date,
        metric_type String,
        value Float64
      ) ENGINE = MergeTree()
      PRIMARY KEY (date, metric_type)
      ORDER BY (date, metric_type)
    SQL

    # Copy data
    execute "INSERT INTO metrics SELECT * FROM metrics_summing"

    # Clean up
    execute "DROP TABLE metrics_summing"
  end

  def down
    raise "Cannot safely reverse engine change without original backup"
  end
end
```

### Zero-Downtime Migrations (Blue-Green Pattern)

For critical production tables, use blue-green deployment:

```ruby
class BluegreenMigration < ActiveRecord::Migration[6.0]
  def up
    # 1. Create new table (green)
    execute <<~SQL
      CREATE TABLE events_v2 (
        id UInt32,
        timestamp DateTime,
        new_field String
      ) ENGINE = MergeTree()
      PRIMARY KEY (id, timestamp)
      ORDER BY (id, timestamp)
    SQL

    # 2. Copy existing data
    execute "INSERT INTO events_v2 SELECT id, timestamp, '' FROM events"

    # 3. In application code: write to both old and new
    # (requires code changes in app)

    # 4. Wait for backlog to drain
    # (verify all new data in events_v2)

    # 5. Switch readers to events_v2
    # (more code changes)

    # 6. In next migration: rename
    execute "RENAME TABLE events TO events_v1"
    execute "RENAME TABLE events_v2 TO events"
  end
end
```

This requires application-level routing changes but eliminates downtime.

### Rollback Strategy (No Rollback Support)

ClickHouse has no automatic rollback:

```ruby
class IrreversibleMigration < ActiveRecord::Migration[6.0]
  def up
    # High-risk operation
    execute "DROP TABLE IF EXISTS temp_data"
  end

  # Explicitly irreversible
  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot restore dropped table"
  end
end
```

**Best practice:** For irreversible operations, back up data before running the migration.

### Testing Migrations on Realistic Data Scale

```ruby
# Prepare test environment
class MigrationSafetyTest < Minitest::Test
  def setup
    # 1. Export schema and sample data from production
    # 2. Create staging cluster with realistic data
    # 3. Run migration on staging
    # 4. Verify:
    #    - Migration completes in acceptable time
    #    - Data integrity is maintained
    #    - Query performance unchanged or improved
    # 5. Check resource usage (disk, memory)
  end

  def test_migration_performance
    start_time = Time.now
    
    # Run migration
    Rake::Task['db:migrate'].invoke
    
    elapsed = Time.now - start_time
    assert elapsed < 60, "Migration took #{elapsed}s, max 60s expected"
  end
end
```

### Migration Safety Checklist

Before running any migration in production:

- [ ] Schema change tested on staging cluster with production data volume
- [ ] Backup of affected table(s) created
- [ ] Migration execution time measured (should be < expected downtime window)
- [ ] Disk space verified (type changes can require 2x space temporarily)
- [ ] Dependent views/models reviewed and updated if needed
- [ ] Cluster members synchronized (replicated tables)
- [ ] Rollback plan documented (even if manual)
- [ ] Query performance impact assessed (especially index changes)
- [ ] Team notified of maintenance window

### Gotchas

**Not Rollable:** All ClickHouse DDL is immediate and permanent. Thoroughly test migrations
first.

**ALTER on Large Tables Locks:** Even "metadata-only" ALTERs can briefly lock large tables during
merge operations.

**Async Mutations:** UPDATE and DELETE operations are asynchronous. Query `system.mutations` to
track progress.

---

## Engine-Specific Schema

### MergeTree Family Overview

ClickHouse provides specialized table engines for different workloads. All production engines
inherit from MergeTree.

| Engine | Best For | Key Feature |
|--------|----------|------------|
| MergeTree | General OLAP | Fast inserts + aggregations |
| ReplicatedMergeTree | HA clusters | Automatic replication |
| SummingMergeTree | Pre-aggregated metrics | Auto-sum on merge |
| AggregatingMergeTree | State aggregation | Efficient state storage |
| ReplacingMergeTree | Slowly changing dimensions | Versioned rows with FINAL |
| CollapsingMergeTree | Signed changes | Pair-wise cancellation |

Choose based on data pattern and query characteristics.

### MergeTree (Basic OLAP)

```ruby
class CreateUsersTable < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE users (
        id UInt32,
        name String,
        email String,
        created_at DateTime,
        updated_at DateTime
      ) ENGINE = MergeTree()
      PRIMARY KEY (id)
      ORDER BY (id, created_at)
    SQL
  end
end
```

**Requirements:**
- ORDER BY is mandatory (defines physical storage order)
- PRIMARY KEY optional but recommended (for query optimization)

### ReplicatedMergeTree (Cluster Replication)

```ruby
class CreateReplicatedUsers < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE IF NOT EXISTS users
      ON CLUSTER 'default' (
        id UInt32,
        name String,
        email String,
        created_at DateTime
      ) ENGINE = ReplicatedMergeTree(
        '/clickhouse/tables/{database}/{table}/{shard}',
        '{replica}'
      )
      PRIMARY KEY (id)
      ORDER BY (id, created_at)
    SQL
  end
end
```

ZooKeeper path patterns:
- `{database}`: Replaced with actual database name
- `{table}`: Replaced with table name
- `{shard}`: Shard number (from cluster config)
- `{replica}`: Replica identifier

All replicas must use the same table definition. Use `ON CLUSTER` for DDL propagation.

### SummingMergeTree (Pre-Aggregated Metrics)

```ruby
class CreateDailyMetricsSumming < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE daily_metrics (
        date Date,
        event_type String,
        user_country String,
        count UInt64,
        revenue Float64
      ) ENGINE = SummingMergeTree()
      PRIMARY KEY (date, event_type, user_country)
      ORDER BY (date, event_type, user_country)
    SQL
  end
end
```

During merges, SummingMergeTree automatically sums numeric columns (count, revenue) for identical
PRIMARY KEY rows. Reduces storage and speeds aggregations.

```ruby
# Query with final aggregation
Event.where(date: Date.today).group(:event_type).sum(:count)
# Sums already-aggregated metrics, very fast
```

### AggregatingMergeTree (State Aggregation)

```ruby
class CreateUserStateAgg < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE user_metrics_agg (
        date Date,
        user_id UInt32,
        unique_sessions AggregateFunction(uniq, UInt32),
        max_session_duration AggregateFunction(max, UInt32)
      ) ENGINE = AggregatingMergeTree()
      PRIMARY KEY (date, user_id)
      ORDER BY (date, user_id)
    SQL
  end
end
```

AggregatingMergeTree stores partially-computed aggregate states (using `-State` combinators).
Perfect for complex metrics requiring stateful aggregation.

```ruby
# Insert pre-computed states
insert_query = <<~SQL
  INSERT INTO user_metrics_agg
  SELECT
    toDate(timestamp) as date,
    user_id,
    uniqState(session_id) as unique_sessions,
    maxState(duration) as max_session_duration
  FROM raw_sessions
  GROUP BY date, user_id
SQL
```

### ReplacingMergeTree (Slowly Changing Dimensions)

```ruby
class CreateUsersWithVersioning < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE users (
        id UInt32,
        name String,
        email String,
        status String,
        version UInt32,
        updated_at DateTime
      ) ENGINE = ReplacingMergeTree(version)
      PRIMARY KEY (id)
      ORDER BY (id, updated_at)
    SQL
  end
end
```

ReplacingMergeTree keeps only the highest `version` for each PRIMARY KEY. During merges, older
versions are discarded.

```ruby
# Version increments on updates
class User < ApplicationRecord
  before_save :increment_version

  def increment_version
    self.version = (self.version || 0) + 1
  end
end

# Query with FINAL for deduplication
User.final.where(id: 123)
# Returns only the latest version of each user
```

### CollapsingMergeTree (Streaming Changes)

```ruby
class CreateEventStream < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE events_stream (
        timestamp DateTime,
        user_id UInt32,
        action String,
        sign Int8
      ) ENGINE = CollapsingMergeTree(sign)
      PRIMARY KEY (timestamp, user_id)
      ORDER BY (timestamp, user_id)
    SQL
  end
end
```

CollapsingMergeTree uses a `sign` column: `+1` for insert, `-1` for cancellation. Pair-wise rows
with opposite signs cancel out during merges (net effect).

```ruby
# Insert new event
ActiveRecord::Base.connection.execute(
  "INSERT INTO events_stream VALUES (now(), 123, 'click', 1)"
)

# Cancel/correct event
ActiveRecord::Base.connection.execute(
  "INSERT INTO events_stream VALUES (now(), 123, 'click', -1)"
)
# Net result: event never happened (both rows cancel)
```

### Log Family (In-Memory Temporary)

```ruby
class CreateTemporaryBuffer < ActiveRecord::Migration[6.0]
  def up
    # Fast insert, suitable for temporary buffering
    execute <<~SQL
      CREATE TABLE logs_buffer (
        timestamp DateTime,
        level String,
        message String
      ) ENGINE = TinyLog()
    SQL
  end
end
```

Log engines (TinyLog, StripeLog, Log) store data in memory or simple sequential files. Suitable
for temporary tables or caches, not production data.

### Table Settings (Index Granularity & Storage)

```ruby
class CreateMetricsWithOptimization < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE metrics_optimized (
        timestamp DateTime,
        metric_type String,
        value Float64
      ) ENGINE = MergeTree()
      PRIMARY KEY (metric_type, timestamp)
      ORDER BY (metric_type, timestamp)
      SETTINGS
        index_granularity = 8192,
        index_granularity_bytes = 10485760,
        compress_primary_key = 1,
        min_compress_block_size = 65536,
        max_compress_block_size = 1048576
    SQL
  end
end
```

Key settings:
- `index_granularity`: Rows per index mark (larger = fewer marks, less memory)
- `index_granularity_bytes`: Approximate bytes per mark
- `compress_primary_key`: Enable primary key compression
- Storage format: Wide vs Compact (wide = slower writes, compact = faster aggregations)

### Creating Engine-Specific Indexes

```ruby
class AddOptimizationIndexes < ActiveRecord::Migration[6.0]
  def up
    # minmax: Useful for range queries
    execute "ALTER TABLE events ADD INDEX idx_timestamp_minmax timestamp " \
            "TYPE minmax GRANULARITY 1"

    # set: Useful for IN queries and specific value lookups
    execute "ALTER TABLE events ADD INDEX idx_status_set status " \
            "TYPE set(10) GRANULARITY 1"

    # bloom_filter: Probabilistic set membership, good for rare values
    execute "ALTER TABLE events ADD INDEX idx_user_id_bloom user_id " \
            "TYPE bloom_filter GRANULARITY 1"

    # Special index for complex expressions
    execute "ALTER TABLE events ADD INDEX idx_hour_minmax " \
            "toHour(timestamp) TYPE minmax GRANULARITY 1"
  end
end
```

### Choosing Engine for Workload

**Use MergeTree when:**
- General-purpose analytics
- Mixed workloads (aggregations + raw queries)
- Frequent schema changes

**Use SummingMergeTree when:**
- Pre-aggregated metrics (time-series)
- Daily/weekly summaries
- Financial data (accumulating totals)

**Use ReplacingMergeTree when:**
- Slowly changing dimensions
- User profiles, product catalogs
- Deduplication via FINAL needed

**Use CollapsingMergeTree when:**
- Stream processing with corrections
- Real-time event cancellation
- Complex streaming pipelines

**Use ReplicatedMergeTree when:**
- High availability required
- Multi-datacenter deployment
- Automated failover needed

### Migration Between Engines

```ruby
class MigrateFromSummingToMergeTree < ActiveRecord::Migration[6.0]
  def up
    # Create new table
    execute <<~SQL
      CREATE TABLE metrics_new (
        date Date,
        event_type String,
        count UInt64
      ) ENGINE = MergeTree()
      PRIMARY KEY (date, event_type)
      ORDER BY (date, event_type)
    SQL

    # Copy data (may need aggregation adjustments)
    execute "INSERT INTO metrics_new SELECT * FROM metrics"

    # Swap
    execute "RENAME TABLE metrics TO metrics_summing"
    execute "RENAME TABLE metrics_new TO metrics"

    # Clean up
    execute "DROP TABLE metrics_summing"
  end
end
```

### Gotchas

**Can't Change Engine Without Recreation:** Changing from SummingMergeTree to MergeTree requires
full table recreation and data migration.

**PRIMARY KEY Not Unique:** Allows duplicates. ReplacingMergeTree with FINAL is needed for
deduplication.

**Index Granularity Affects Memory:** Smaller granularity = more index marks = more memory used.
Balance query speed vs memory.

---

## Related Operations

### Partition Management

```ruby
# List partitions
partitions = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT partition, name, rows, bytes_on_disk
  FROM system.parts
  WHERE database = currentDatabase() AND table = 'events'
  ORDER BY modification_time DESC
SQL

# Drop old partition
execute "ALTER TABLE events DROP PARTITION '202501'"

# Detach partition (keep data, remove from table)
execute "ALTER TABLE events DETACH PARTITION '202501'"

# Attach partition back
execute "ALTER TABLE events ATTACH PARTITION '202501'"

# Freeze partition for backup
execute "ALTER TABLE events FREEZE PARTITION '202501'"
```

### TTL (Time-To-Live)

```ruby
class CreateEventTableWithTTL < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE events (
        timestamp DateTime,
        event_type String,
        user_id UInt32
      ) ENGINE = MergeTree()
      PRIMARY KEY (timestamp, event_type)
      ORDER BY (timestamp, event_type)
      TTL timestamp + INTERVAL 90 DAY
    SQL
  end
end
```

TTL automatically deletes rows older than the specified interval. Runs during merge operations.

### Dictionaries

```ruby
# Dictionaries cache reference data for lookups
execute <<~SQL
  CREATE DICTIONARY user_status (
    id UInt32,
    status String
  ) PRIMARY KEY id
  SOURCE(CLICKHOUSE(QUERY 'SELECT id, status FROM user_statuses'))
  LIFETIME(MIN 10 MAX 3600)
  LAYOUT(HASHED())
SQL

# Use dictionary in queries
execute <<~SQL
  SELECT
    user_id,
    dictGet('user_status', 'status', user_id) as status
  FROM events
SQL
```

---

## Performance Tuning

### Index Analysis

```ruby
# Analyze which indexes are effective
index_stats = ActiveRecord::Base.connection.execute(<<~SQL)
  SELECT
    name,
    type,
    creation_time
  FROM system.indexes
  WHERE table = 'events'
SQL

# Monitor query performance improvements after index addition
before_time = Time.now
result = Event.where(status: 'active', date: Date.today).count
after_time = Time.now

puts "Query took #{(after_time - before_time) * 1000}ms"
```

### Partition Key Selection

Partition key affects query performance significantly:

```ruby
# Good: Partition by date (time-series data)
execute <<~SQL
  CREATE TABLE metrics (
    timestamp DateTime,
    value Float64
  ) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(timestamp)
  PRIMARY KEY (timestamp)
SQL

# Avoid: Too many partitions (each partition = separate merge)
execute <<~SQL
  CREATE TABLE metrics_bad (
    timestamp DateTime,
    value Float64
  ) ENGINE = MergeTree()
  PARTITION BY timestamp  -- Creates partition per second!
SQL
```

---

## Best Practices

### Schema Design Patterns

**1. Event Sourcing with Materialized Views**

```ruby
# Raw event table (immutable append-only)
class CreateRawEvents < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE raw_events (
        timestamp DateTime,
        event_id UUID,
        user_id UInt32,
        event_type String,
        properties String
      ) ENGINE = MergeTree()
      PARTITION BY toYYYYMM(timestamp)
      PRIMARY KEY (event_id)
      ORDER BY (event_id, timestamp)
    SQL

    # Materialized view for aggregates
    execute <<~SQL
      CREATE TABLE event_metrics (
        date Date,
        event_type String,
        count UInt64
      ) ENGINE = SummingMergeTree()
      PRIMARY KEY (date, event_type)
      ORDER BY (date, event_type)
    SQL

    # Automatic aggregation
    execute <<~SQL
      CREATE MATERIALIZED VIEW raw_events_to_metrics
      TO event_metrics AS
      SELECT
        toDate(timestamp) as date,
        event_type,
        count() as count
      FROM raw_events
      GROUP BY date, event_type
    SQL
  end
end
```

**2. Dimension Tables with Versioning**

```ruby
class CreateUserDimension < ActiveRecord::Migration[6.0]
  def up
    execute <<~SQL
      CREATE TABLE user_dim (
        user_id UInt32,
        name String,
        country String,
        status String,
        version UInt32,
        valid_from DateTime,
        valid_to DateTime
      ) ENGINE = ReplacingMergeTree(version)
      PRIMARY KEY (user_id)
      ORDER BY (user_id, valid_from)
    SQL
  end
end

# Model for dimension updates
class UserDim < ApplicationRecord
  self.table_name = "user_dim"

  def self.update_user(user_id, attributes)
    # Get current max version
    current = order(version: :desc).find_by(user_id: user_id)
    version = (current&.version || 0) + 1

    # Insert new version
    create!(
      user_id: user_id,
      version: version,
      valid_from: Time.now,
      valid_to: Time.at(0),
      **attributes
    )
  end

  def self.current_state(user_id)
    final.where(user_id: user_id).first
  end
end
```

**3. Time-Series Metrics with Rollups**

```ruby
class CreateMetricsRollups < ActiveRecord::Migration[6.0]
  def up
    # Raw metrics (1-minute resolution)
    execute <<~SQL
      CREATE TABLE metrics_raw (
        timestamp DateTime,
        metric_name String,
        value Float64
      ) ENGINE = MergeTree()
      PARTITION BY toYYYYMM(timestamp)
      PRIMARY KEY (metric_name, timestamp)
      ORDER BY (metric_name, timestamp)
      TTL timestamp + INTERVAL 30 DAY
    SQL

    # Hourly rollup
    execute <<~SQL
      CREATE TABLE metrics_1h (
        timestamp DateTime,
        metric_name String,
        count UInt64,
        min Float64,
        max Float64,
        avg Float64
      ) ENGINE = SummingMergeTree()
      PARTITION BY toYYYYMM(timestamp)
      PRIMARY KEY (metric_name, timestamp)
      ORDER BY (metric_name, timestamp)
      TTL timestamp + INTERVAL 1 YEAR
    SQL

    # Automatic hourly aggregation
    execute <<~SQL
      CREATE MATERIALIZED VIEW metrics_raw_to_1h
      TO metrics_1h AS
      SELECT
        toStartOfHour(timestamp) as timestamp,
        metric_name,
        count() as count,
        min(value) as min,
        max(value) as max,
        avg(value) as avg
      FROM metrics_raw
      GROUP BY timestamp, metric_name
    SQL
  end
end
```

### Scalability Considerations

**Sharding Strategy:**
- Partition data by natural dimensions (user_id, country, tenant_id)
- Avoid hot shards (ensure even distribution)
- Monitor shard-to-replica rebalancing

**Replication Strategy:**
- 2-3 replicas for HA (more replicas = more network overhead)
- Place replicas across datacenters for disaster recovery
- Monitor replica lag with `system.replicas`

### Backup Strategy

```ruby
# Freeze partitions for backup
freeze_result = ActiveRecord::Base.connection.execute(
  "ALTER TABLE events FREEZE PARTITION '202501'"
)

# Copy frozen data
# frozen data typically in: /var/lib/clickhouse/shadow/

# Backup metadata
metadata = ActiveRecord::Base.connection.execute(
  "SELECT create_table_query FROM system.tables WHERE name = 'events'"
).first

File.write("backups/events_schema.sql", metadata['create_table_query'])
```

---

## Integration with Rails

### Adapting ActiveRecord Conventions

ClickHouse doesn't follow all Rails conventions:

```ruby
class Event < ApplicationRecord
  # Explicitly set table name (ClickHouse is case-sensitive)
  self.table_name = "events"

  # Disable Rails timestamp columns (use ClickHouse DateTime columns instead)
  self.record_timestamps = false

  # No validation of table structure (migration might not have run yet)
  skip_db_structure_load_for = :all

  # Custom primary key if not 'id'
  self.primary_key = "event_id"
end
```

### Connection Per-Model

```ruby
class AnalyticsEvent < ApplicationRecord
  self.table_name = "events"
  establish_connection :analytics  # Use 'analytics' connection from database.yml
end

class Event < ApplicationRecord
  self.table_name = "events"
  establish_connection :default    # Use 'default' connection
end
```

### Avoiding Common Pitfalls

**1. Avoid N+1 queries with preload:**

```ruby
# Bad: N+1 queries
events.each { |e| puts e.user.name }  # Loads user for each event

# Good: Join or preload
Event.joins(:user).select('events.*, users.name')
```

**2. Use batch operations for large inserts:**

```ruby
# Bad: One insert per row
events.each { |e| Event.create(e) }

# Good: Batch insert
Event.insert_all(events, batch_size: 10_000)
# Uses JSONEachRow for efficiency
```

**3. Test schema changes on production-like data:**

```ruby
# In test suite
def test_schema_migration
  # Load production data schema
  # Run migration
  # Assert on performance and data integrity
end
```

---

## Testing & Tooling

### Inspecting Schema Programmatically

```ruby
# DSL for schema inspection
class SchemaInspector
  def initialize(connection = ActiveRecord::Base.connection)
    @connection = connection
  end

  def table_summary(table_name)
    {
      engine: engine_type(table_name),
      rows: row_count(table_name),
      size_mb: size_mb(table_name),
      columns: column_details(table_name),
      indexes: index_details(table_name),
    }
  end

  private

  def engine_type(table_name)
    @connection.execute(
      "SELECT engine FROM system.tables WHERE name = '#{table_name}'"
    ).first&.dig("engine")
  end

  def row_count(table_name)
    @connection.execute(
      "SELECT total_rows FROM system.tables WHERE name = '#{table_name}'"
    ).first&.dig("total_rows") || 0
  end

  def size_mb(table_name)
    bytes = @connection.execute(
      "SELECT total_bytes FROM system.tables WHERE name = '#{table_name}'"
    ).first&.dig("total_bytes") || 0
    (bytes / 1024.0 / 1024.0).round(2)
  end

  def column_details(table_name)
    @connection.columns(table_name).map do |col|
      { name: col.name, type: col.type }
    end
  end

  def index_details(table_name)
    @connection.indexes(table_name).map do |idx|
      { name: idx.name, columns: idx.columns }
    end
  end
end

# Usage
inspector = SchemaInspector.new
puts inspector.table_summary("events").to_yaml
```

### Generating Fixtures from Production Schema

```ruby
# Export table structure for fixtures
class FixtureGenerator
  def initialize(table_name)
    @table_name = table_name
    @connection = ActiveRecord::Base.connection
  end

  def generate_sql
    result = @connection.execute(
      "SELECT create_table_query FROM system.tables " \
      "WHERE name = '#{@table_name}'"
    )
    result.first&.dig("create_table_query")
  end

  def generate_sample_data(limit: 1000)
    @connection.execute(
      "SELECT * FROM #{@table_name} LIMIT #{limit}"
    )
  end

  def export_to_file(filepath)
    sql = generate_sql
    File.write(filepath, sql)
    puts "Schema exported to #{filepath}"
  end
end

# Usage
gen = FixtureGenerator.new("events")
gen.export_to_file("db/fixtures/events.sql")
```

---

## References

### Related Documentation

- [ACTIVE_RECORD.md](./ACTIVE_RECORD.md) - Query operations, relation extensions
- [ARCHITECTURE.md](./ARCHITECTURE.md) - System design, type system, connection pooling
- [CLICKHOUSE_FEATURES.md](./CLICKHOUSE_FEATURES.md) - ClickHouse-specific features

### External Resources

- [ClickHouse Table Engines](https://clickhouse.com/docs/en/engines/table-engines/)
- [ClickHouse DDL Statements](https://clickhouse.com/docs/en/sql-reference/statements/)
- [System Tables Reference](https://clickhouse.com/docs/en/operations/system-tables/)
- [ClickHouse Schema Optimization](https://clickhouse.com/docs/en/optimize/schema-design/)

---

**Last Updated:** February 2025
**Version:** v0.2.0+
