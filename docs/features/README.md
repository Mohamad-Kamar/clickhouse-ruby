# ClickhouseRuby v0.2.0 Features Guide

This guide documents the 9 new features added in v0.2.0, organized by category with usage examples and best practices.

## Overview

### Type System Enhancements

**[Enum Type](./enum_type.md)** - Fixed set of predefined string values
- `Enum8('active'=1, 'inactive'=2)` support
- Automatic string-to-integer mapping
- Use when columns have known fixed values (status, category, etc.)

**[Decimal Type](./decimal_type.md)** - Arbitrary precision financial math
- `Decimal(precision, scale)` support via BigDecimal
- Use for financial data (prices, balances, rates)
- Avoids floating-point rounding errors

### Client Enhancements

**[HTTP Compression](./http_compression.md)** - Automatic gzip compression
```ruby
ClickhouseRuby.configure do |config|
  config.compression = 'gzip'
  config.compression_threshold = 1024  # Only compress payloads > 1KB
end
```
- Reduces network bandwidth for large payloads
- Zero-dependency implementation (uses built-in Zlib)

**[Retry Logic](./retry_logic.md)** - Automatic retries with exponential backoff
```ruby
ClickhouseRuby.configure do |config|
  config.max_retries = 3
  config.initial_backoff = 1.0
  config.backoff_multiplier = 1.6
  config.max_backoff = 120
end
```
- Auto-retries on connection errors and HTTP 5xx/429
- Does NOT retry on query syntax errors
- Configurable jitter strategies

**[Result Streaming](./streaming.md)** - Memory-efficient large result processing
```ruby
client.stream_execute('SELECT * FROM huge_table') do |row|
  process_row(row)
end
```
- Constant memory usage regardless of result size
- Yields rows one at a time
- Perfect for data processing pipelines

### ActiveRecord Query Extensions

**[PREWHERE Clause](./prewhere.md)** - Query optimization by pre-filtering
```ruby
# Filters before reading all columns
Event.prewhere(date: Date.today).where(status: 'active')
# SELECT * FROM events PREWHERE date = '2024-02-02' WHERE status = 'active'
```

**[FINAL Modifier](./final.md)** - Deduplication for ReplacingMergeTree
```ruby
# Returns deduplicated results
User.final.where(id: 123)
# SELECT * FROM users FINAL WHERE id = 123
```
- Use for accuracy when you need latest version of each row
- Performance cost: 2-10x slower (merges at query time)

**[SAMPLE Clause](./sample.md)** - Approximate queries on large tables
```ruby
# 10% sample of data
Event.sample(0.1).count
# SELECT count() FROM events SAMPLE 0.1

# At least 10,000 rows
Event.sample(10000).average(:amount)
# SELECT avg(amount) FROM events SAMPLE 10000
```

**[SETTINGS DSL](./settings_dsl.md)** - Per-query ClickHouse configuration
```ruby
# Increase parallelism for this query
Event.settings(max_threads: 4).where(active: true).count
# SELECT count() FROM events WHERE active = 1 SETTINGS max_threads = 4
```

## Feature Categories

### Type System (lib/clickhouse_ruby/types/)
- `Enum` - Enum8/Enum16 with bidirectional mapping
- `Decimal` - Precision arithmetic with automatic variant selection

### Client (lib/clickhouse_ruby/client.rb)
- `stream_execute` - Memory-efficient result streaming
- Configuration for compression, retry, timeout options

### ActiveRecord (lib/clickhouse_ruby/active_record/relation_extensions.rb)
- `.final` - Deduplication modifier
- `.sample(fraction or count)` - Approximate queries
- `.prewhere(conditions)` - Pre-filter optimization
- `.settings(options)` - Per-query configuration

## Quick Reference

| Feature | Use Case | Performance | Complexity |
|---------|----------|-------------|-----------|
| Enum | Fixed values (status, type) | No impact | Low |
| Decimal | Financial data | No impact | Low |
| Compression | Large payloads | Reduces bandwidth | Low |
| Retry | Network resilience | Adds latency on retry | Low |
| Streaming | Large results | Constant memory | Medium |
| PREWHERE | Query optimization | Faster queries | Low |
| FINAL | Accuracy | 2-10x slower | Low |
| SAMPLE | Approximate analysis | Much faster | Medium |
| SETTINGS | Query tuning | Varies | Low |

## Common Gotchas

### Enum Type
- Values must be predefined in table schema
- Cannot insert unknown values
- Ordering is numeric (1, 2, 3), not alphabetical

### Decimal Type
- Use `BigDecimal` in Ruby, NOT `Float`
- Scale cannot exceed precision
- Decimal32 max 9 digits, Decimal64 max 18 digits

### HTTP Compression
- Overhead for small payloads (<1MB)
- Set `compression_threshold` appropriately

### Retry Logic
- INSERT operations not idempotent by default
- Use `query_id` for safe retries on inserts
- Does NOT retry on QueryError (syntax errors)

### Streaming
- Cannot use with FINAL
- Cannot use with aggregate functions
- SELECT * works, SELECT col1, col2 also works

### PREWHERE
- Doesn't work with multiple JOINs
- Requires MergeTree family tables
- Auto-optimization often better than manual use

### FINAL
- High performance cost
- Use for correctness, not speed
- Requires specific table engines (ReplacingMergeTree, etc.)

### SAMPLE
- Requires `SAMPLE BY` clause on table creation
- Results are approximate (not exact)
- Counts need adjustment or use `_sample_factor`

### SETTINGS
- Must be at END of query
- Unknown settings cause ClickHouse errors
- Boolean values are 0/1, not true/false

## Documentation Files

- **Individual feature docs** - Detailed research, gotchas, best practices, and implementation details
- **This README** - Quick reference and overview
- **Main README** - General library usage and setup

## See Also

- [ActiveRecord Integration](../ACTIVE_RECORD.md) - Schema creation, mutations, type mapping
- [Architecture](../ARCHITECTURE.md) - Design overview and component details
- [Main README](../../README.md) - Installation, basic usage, error handling

---

**All features are production-ready and fully tested.** See individual feature docs for detailed usage patterns.
