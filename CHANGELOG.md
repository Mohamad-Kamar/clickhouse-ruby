# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-02-02

### Added

#### ActiveRecord Query Extensions
- **FINAL modifier** - Deduplication support for ReplacingMergeTree and CollapsingMergeTree tables
  - Methods: `final`, `final!`, `final?`, `unscope_final`
  - Auto-adds required settings when combined with PREWHERE
  - Example: `User.final.where(id: 123)`

- **SAMPLE clause** - Approximate queries on large datasets for performance
  - Methods: `sample(ratio_or_rows, offset: nil)`, `sample!`, `sample_value`, `sample_offset`
  - Supports fractional sampling (0.1 = 10%) and absolute row counts
  - Preserves Integer vs Float distinction (1 = "at least 1 row", 1.0 = "100% of data")
  - Example: `Event.sample(0.1).count`

- **PREWHERE clause** - Query optimization that filters before reading all columns
  - Methods: `prewhere(opts)`, `prewhere!`, `prewhere_values`, `prewhere.not(...)`
  - Supports hash conditions, string conditions with placeholders, ranges, and Arel nodes
  - Automatically optimized by ClickHouse when enabled
  - Example: `Event.prewhere(date: Date.today).where(status: 'active')`

- **SETTINGS DSL** - Per-query ClickHouse configuration
  - Methods: `settings(opts)`, `settings!`, `query_settings`
  - Normalizes boolean values (true/false → 1/0)
  - Quotes string values automatically
  - Example: `Event.settings(max_threads: 4, async_insert: true).all`

#### Internal Improvements
- Arel visitor integration for ClickHouse-specific SQL clauses
- Proper SQL clause ordering: SELECT FROM [FINAL] [SAMPLE] [PREWHERE] [WHERE] [GROUP BY] [ORDER BY] [LIMIT] [SETTINGS]
- RelationExtensions#build_arel override to attach ClickHouse state to Arel AST

#### Type System Extensions
- **Enum Type** - Support for Enum8 and Enum16 with string-to-integer mapping
  - Methods: `cast`, `serialize`, `deserialize`
  - Validation of enum values
  - Example: `field_type = :Enum8` with values mapped via schema

- **Decimal Type** - Arbitrary precision decimal support via BigDecimal
  - Auto-mapping to Decimal32/64/128/256 based on precision
  - Example: `field_type = :Decimal` with precision and scale

#### Reliability Improvements
- **Retry Logic** - Exponential backoff with jitter for transient failures
  - Default: 1.6x multiplier, up to 120 seconds max backoff
  - Configurable via `initial_backoff`, `backoff_multiplier`, `max_backoff`, `max_retries`
  - Only retries transient errors (ConnectionError, Timeout, HTTP 5xx/429)
  - Non-retriable: QueryError (syntax errors), HTTP 4xx

- **Result Streaming** - Memory-efficient processing of large result sets
  - Method: `stream_execute(sql) { |row| ... }`
  - Yields rows one at a time using JSONEachRow format
  - Constant memory usage regardless of result size
  - Example: `client.stream_execute('SELECT * FROM huge_table') { |row| process(row) }`

#### Performance Improvements
- **HTTP Compression** - gzip compression for request/response
  - Configuration: `compression: 'gzip'`, `compression_threshold: 1024`
  - Built-in Zlib support (no external dependencies)
  - Headers: `Content-Encoding: gzip`, `Accept-Encoding: gzip`
  - Beneficial for large payloads (>1MB)

### Changed
- ActiveRecord relation extension architecture for better feature organization
- Improved documentation with examples for all new features

### Known Limitations
- PREWHERE doesn't work with multiple JOINs (ClickHouse limitation)
- SAMPLE requires table created with SAMPLE BY clause
- Streaming cannot be used with FINAL or aggregate functions
- HTTP compression has overhead for small payloads

## [0.1.0] - 2026-01-31

### Added

#### Core Features
- HTTP client with connection pooling for ClickHouse communication
- SSL/TLS support with certificate verification **enabled by default** (security fix vs existing gems)
- Configurable timeouts (connect, read, write)
- Basic authentication (username/password via headers)
- Connection health checks (ping)

#### Error Handling (Critical Fix)
- Proper HTTP status code checking - **never silently ignores errors**
- Clear exception hierarchy (`ClickhouseRuby::Error` → `QueryError`, `ConnectionError`, etc.)
- ClickHouse error code extraction and mapping to specific exception classes
- Actionable error messages with full context (SQL, error code, HTTP status)

#### Type System (Critical Fix)
- **AST-based type parser** - properly handles nested types (fixes regex-based parsing issues)
- Support for all basic types: String, Int8-256, UInt8-256, Float32/64, Bool
- Date/DateTime/DateTime64 with timezone awareness
- UUID with format validation
- Complex types: Array(T), Map(K,V), Tuple(T1,T2,...), Nullable(T), LowCardinality(T)
- Bidirectional type conversion (Ruby ↔ ClickHouse)

#### Query Execution
- SELECT queries with JSONCompact format
- Result object with Enumerable interface
- Column type information in results
- Query-level SETTINGS support

#### Bulk Insert
- JSONEachRow format support (5x faster than VALUES syntax)
- INSERT with SETTINGS support (async_insert, etc.)
- Batch insert API with proper error handling

#### ActiveRecord Integration
- Connection adapter registration (`adapter: clickhouse`)
- Basic CRUD operations with proper error propagation
- Schema introspection (tables, columns via system tables)
- Arel visitor for ClickHouse SQL dialect
- ALTER TABLE DELETE/UPDATE syntax for mutations
- Rails integration via Railtie

#### Project Infrastructure
- RSpec test suite with unit and integration tests
- WebMock for HTTP mocking in unit tests
- Docker Compose setup for ClickHouse testing
- GitHub Actions CI workflow
- RuboCop configuration

### Security
- SSL certificate verification is ON by default (unlike existing gems)
- Passwords not logged

### Known Limitations
- HTTP protocol only (native TCP protocol planned for future)
- No PREWHERE support yet (planned for v0.2.0)
- No streaming results yet (planned for v0.2.0)
- No migration DSL for table engines/partitions yet (planned for v0.2.0)

## Comparison with Existing Solutions

This gem addresses critical issues found in existing ClickHouse Ruby gems:

| Issue | clickhouse-activerecord | ClickhouseRuby |
|-------|------------------------|--------|
| Silent DELETE failures (#230) | ❌ Fails silently | ✅ Always raises errors |
| Type parsing (#210) | ❌ Regex breaks nested | ✅ AST-based parser |
| SSL verification | ❌ Disabled by default | ✅ Enabled by default |
| PREWHERE support (#228) | ❌ Missing | 🔜 Planned v0.2.0 |
