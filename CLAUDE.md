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

## Testing

- Unit tests use WebMock for HTTP mocking
- Integration tests require `CLICKHOUSE_TEST_INTEGRATION=true` and a running ClickHouse
- Test helpers in `spec/support/clickhouse_helper.rb` provide standard test tables and setup
- Coverage minimum: 80% overall
