# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClickhouseRuby is a lightweight Ruby client for ClickHouse with optional ActiveRecord integration. Key design principles:
- Zero runtime dependencies (uses only Ruby stdlib)
- SSL verification enabled by default
- Never silently fails (always raises on errors, fixing clickhouse-activerecord #230)
- AST-based type parser for complex nested types

## Common Commands

```bash
# Run all tests (unit + integration if CLICKHOUSE_TEST_INTEGRATION=true)
bundle exec rake spec

# Run unit tests only (fast, no ClickHouse required)
bundle exec rake spec_unit

# Run integration tests (requires ClickHouse running)
CLICKHOUSE_TEST_INTEGRATION=true bundle exec rake spec_integration

# Run a single test file
bundle exec rspec spec/unit/clickhouse_ruby/client_spec.rb

# Run tests matching a pattern
bundle exec rspec --example "handles connection errors"

# Lint check
bundle exec rake rubocop

# Auto-fix lint issues
bundle exec rake rubocop_fix

# Run all checks (tests + linting)
bundle exec rake check

# Start local ClickHouse for development
docker-compose up -d
```

## Architecture

### Core Components

**Client Layer** (`lib/clickhouse_ruby/client.rb`)
- Main API: `execute(sql)`, `command(sql)`, `insert(table, rows)`, `ping`
- Uses JSONCompact format for queries, JSONEachRow for inserts (5x faster than VALUES)
- Always checks HTTP status before parsing body

**Connection Management** (`connection.rb`, `connection_pool.rb`)
- Thread-safe connection pool with checkout/checkin pattern
- Health checks before returning connections
- Use `with_connection` block for safe resource management

**Type System** (`lib/clickhouse_ruby/types/`)
- `parser.rb`: Recursive descent AST parser for ClickHouse type strings (handles nested types like `Array(Tuple(String, UInt64))`)
- `registry.rb`: Bidirectional Ruby ↔ ClickHouse type mapping
- Individual type classes handle `cast()`, `serialize()`, `deserialize()`

**Error Handling** (`lib/clickhouse_ruby/errors.rb`)
- Maps 30+ ClickHouse error codes to specific exception classes
- Hierarchy: `Error` → `ConnectionError` / `QueryError` / `TypeCastError` / `PoolError`
- `QueryError` includes `code`, `http_status`, `sql` attributes

**ActiveRecord Integration** (`lib/clickhouse_ruby/active_record/`)
- Optional layer, loaded only when ActiveRecord present
- `connection_adapter.rb`: AR adapter interface implementation
- `arel_visitor.rb`: Arel AST to ClickHouse SQL conversion
- `relation_extensions.rb`: ClickHouse-specific query methods (FINAL, SAMPLE, PREWHERE, SETTINGS)
- `schema_statements.rb`: DDL with ClickHouse-specific options (engines, partition keys)

### Data Flow

```
Client.execute(sql) → ConnectionPool.with_connection → Connection (Net::HTTP)
                   → Response parsing → Type deserialization → Result (Enumerable)
```

## Code Style

- **Frozen string literals**: Required on all files (`# frozen_string_literal: true`)
- **Line length**: 120 characters max
- **String literals**: Double quotes
- **Trailing commas**: Required in multiline arrays/hashes/arguments
- **RSpec context prefixes**: when, with, without, if, unless, for, given

## ActiveRecord Query Extensions (v0.2.0+)

ClickhouseRuby extends ActiveRecord::Relation with ClickHouse-specific query methods:

### FINAL - Deduplication for ReplacingMergeTree

```ruby
# Basic FINAL usage
User.final.where(id: 123)
# SELECT * FROM users FINAL WHERE id = 123

# With aggregation
User.final.group(:status).count
# SELECT status, count() FROM users FINAL GROUP BY status

# Performance note: FINAL can be 2-10x slower (merges at query time)
```

### SAMPLE - Approximate Queries

```ruby
# Fractional sampling (10% of data)
Event.sample(0.1).count
# SELECT count() FROM events SAMPLE 0.1

# Absolute row count (at least 10000 rows)
Event.sample(10000).average(:amount)
# SELECT avg(amount) FROM events SAMPLE 10000

# With offset for reproducibility
Event.sample(0.1, offset: 0.5)
# SELECT * FROM events SAMPLE 0.1 OFFSET 0.5

# Important: Integer 1 = "at least 1 row", Float 1.0 = "100% of data"
Event.sample(1)    # SAMPLE 1 (absolute)
Event.sample(1.0)  # SAMPLE 1.0 (fractional = 100%)
```

### PREWHERE - Query Optimization

```ruby
# Pre-filter before reading all columns
Event.prewhere(date: Date.today).where(status: 'active')
# SELECT * FROM events PREWHERE date = TODAY() WHERE status = 'active'

# String conditions with placeholders
Event.prewhere('date > ?', 1.day.ago).where(active: true)

# Range conditions
Event.prewhere(created_at: 1.week.ago..Time.now)

# Negation
Event.prewhere.not(deleted: true)
# SELECT * FROM events PREWHERE NOT(deleted = 1)
```

### SETTINGS - Per-Query Configuration

```ruby
# Timeout configuration
Event.settings(max_execution_time: 60).all
# SELECT * FROM events SETTINGS max_execution_time = 60

# Multiple settings
Event.settings(max_threads: 4, async_insert: true)
# SELECT * FROM events SETTINGS max_threads = 4, async_insert = 1

# Boolean normalization (true → 1, false → 0)
Event.settings(final: true)
# SELECT * FROM events SETTINGS final = 1

# Chaining with other methods
Event.where(active: true).settings(max_rows_to_read: 1000000)
# SELECT * FROM events WHERE active = 1 SETTINGS max_rows_to_read = 1000000
```

### Combining Features

```ruby
# Complex query with all features
User.final
  .prewhere(created_at: 1.week.ago..)
  .where(status: 'active')
  .sample(0.1)
  .settings(max_threads: 4)
  .order(id: :desc)
  .limit(100)

# Generates SQL with proper clause ordering:
# SELECT * FROM users FINAL
# SAMPLE 0.1
# PREWHERE created_at >= '2026-01-26'
# WHERE status = 'active'
# ORDER BY id DESC
# LIMIT 100
# SETTINGS max_threads = 4

# Note: FINAL + PREWHERE auto-adds optimization settings
```

## Type System Extensions (v0.2.0+)

### Enum Type - Fixed Set of String Values

```ruby
# Enum8 supports up to 256 values, Enum16 up to 65536
# Use in queries
Status.where(status: 'active')
# Maps 'active' string to integer value from enum definition
```

### Decimal Type - Arbitrary Precision

```ruby
# Financial data with exact precision
# Auto-mapped to Decimal32/64/128/256 based on precision

# Use BigDecimal in Ruby (not Float!)
price = BigDecimal('99.9999')
Price.create(amount: price)

# Decimal(P,S) where P = precision (1-76), S = scale (≤ P)
# Decimal32: max 9 digits
# Decimal64: max 18 digits
```

## Client Features (v0.2.0+)

### Retry Logic - Automatic Retries

```ruby
# Configured via configuration
ClickhouseRuby.configure do |config|
  config.max_retries = 3              # How many retries (default 3)
  config.initial_backoff = 1.0        # Starting backoff in seconds (default 1.0)
  config.backoff_multiplier = 1.6     # Backoff multiplier (default 1.6)
  config.max_backoff = 120.0          # Max backoff time (default 120)
  config.retry_jitter = :equal        # Jitter strategy (default :equal)
end

# Jitter strategies for retry_jitter configuration:
# - :full    Random between 0 and calculated delay (high variance, prevents thundering herd)
# - :equal   Half fixed + half random (default, balanced approach)
# - :none    Pure exponential backoff without randomization

# Retries automatically on:
# - ConnectionError (network issues)
# - Timeout
# - HTTP 5xx errors
# - HTTP 429 (rate limit)

# Does NOT retry on:
# - QueryError (syntax errors, invalid SQL)
# - HTTP 4xx errors (client errors)
```

### Result Streaming - Memory Efficient

```ruby
# Stream large results row by row (constant memory)
client.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
end

# Returns Enumerator if no block given
enumerator = client.stream_execute('SELECT * FROM table')
enumerator.each { |row| process(row) }

# Uses JSONEachRow format (one JSON per line)
# Cannot be used with FINAL or aggregate functions
# SELECT * works, SELECT col1, col2 also works
```

### HTTP Compression - Performance

```ruby
# Configured via configuration
ClickhouseRuby.configure do |config|
  config.compression = 'gzip'           # nil = no compression
  config.compression_threshold = 1024   # Minimum size to compress
end

# Uses built-in Zlib (no external gems)
# Headers: Content-Encoding: gzip, Accept-Encoding: gzip
# Beneficial for large payloads (>1MB)
# Small payloads may be slower due to compression overhead

# Automatic behavior:
client.insert('events', large_data_array)  # Compressed if > threshold
result = client.execute('SELECT * FROM huge_table')  # Response decompressed
```

## Testing

- Unit tests use WebMock for HTTP mocking
- Integration tests require `CLICKHOUSE_TEST_INTEGRATION=true` and a running ClickHouse
- Test helpers in `spec/support/clickhouse_helper.rb` provide standard test tables and setup
- Coverage minimum: 80% overall
- ActiveRecord-specific tests require ActiveRecord gem (optional dependency)
- Run `bundle exec rake check` to run all tests and lint checks
