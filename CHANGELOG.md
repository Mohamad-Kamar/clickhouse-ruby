# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- VCR for HTTP interaction recording
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
