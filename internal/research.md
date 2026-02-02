# Research Findings: Ruby/ActiveRecord ClickHouse Integration

> **Last Updated:** 2026-01-31
> **Status:** Research Complete, Implementation Complete for v0.1.0

## Executive Summary

This document captures research findings from analyzing the best ClickHouse client implementations across languages (Go, Python, Node.js, Java) and existing Ruby solutions (clickhouse-activerecord, click_house gem).

## Key Patterns from Best Implementations

### Go clickhouse-go v2 (Best-in-Class)

**Architecture Highlights:**
1. **Dual Protocol Support** - Both HTTP (port 8123) and Native TCP (port 9000)
2. **Interface Abstraction** - `nativeTransport` interface allows protocol swapping transparently
3. **Sophisticated Connection Pool** - Circular queue with automatic expiration, configurable limits
4. **No Query Builder** - SQL-first philosophy with safe parameter binding

**Type System:**
- 50+ column type implementations in `lib/column/`
- Implements `column.Interface` with `Append`, `ScanRow`, `Decode`, `Encode`
- Smart type conversions with precision protection
- Server context awareness for timezone handling

**Error Handling:**
- Three-level model: Server Exception → Column Error → Operation Error
- Rich error context: column name, type, conversion details
- Connection health checks (`isBad()`) before returning pooled connections

**Developer Experience Patterns:**
- Struct mapping with reflection-based marshaling
- Context extensions for query options (settings, query ID, progress)
- Dual interface: Native API for performance, `database/sql` for compatibility
- Structured logging with slog integration

### clickhouse-activerecord Analysis

**Current Issues (Why Build New):**

| Issue | Severity | Description | Our Fix |
|-------|----------|-------------|---------|
| #228 | High | Missing PREWHERE support | 🔜 v0.2.0 |
| #230 | Critical | Silent DELETE failures | ✅ Always check HTTP status |
| #210 | High | Regex-based type parsing breaks | ✅ AST-based parser |
| #224 | Medium | Type downcasting in schema dumper | 🔜 v0.2.0 |
| SSL | Critical | SSL verification disabled | ✅ Enabled by default |

**Patterns to AVOID:**
1. **SSL Verification Disabled** - Security vulnerability → ✅ Fixed
2. **Silent Error Failures** - `exec_delete` ignores HTTP status codes → ✅ Fixed
3. **Regex-Based Type Parsing** - Fails for nested Array/Map/Tuple → ✅ Fixed
4. **Missing PREWHERE** - Major performance impact → 🔜 v0.2.0
5. **Aggregation Type Casting** - `argMaxIf` returns wrong types → 🔜 Later

### ActiveRecord Adapter Pattern

**Required Interface Methods:**

**Connection Management:** ✅ Implemented
- `new_client`, `active?`, `connected?`, `disconnect!`, `reconnect!`, `verify!`
- `configure_connection`, `get_database_version`

**Query Execution:** ✅ Implemented
- `execute`, `perform_query`, `exec_insert`, `exec_update`, `exec_delete`
- `cast_result`, `affected_rows`

**Type System:** ✅ Implemented
- `initialize_type_map(m)`, `native_database_types`, `type_to_sql`

**Transaction Control:** ✅ Implemented (as no-ops)
- `begin_db_transaction`, `commit_db_transaction`, `rollback_db_transaction`
- Note: ClickHouse has limited transaction support

**Error Handling:** ✅ Implemented
- `translate_exception(exception, message:, sql:, binds:)`

**SQL Generation:** ✅ Implemented
- `arel_visitor`, `quote_column_name`, `quote_table_name`

**Schema Operations:** ✅ Implemented
- `create_table`, `drop_table`, `add_column`, `columns`, `indexes`

## Design Decisions - Implementation Status

### 1. HTTP-Only Initially ✅ IMPLEMENTED

**Rationale:**
- Simpler implementation
- Works through proxies/firewalls
- Adequate for most use cases
- Can add native protocol later if needed

### 2. AST-Based Type Parser ✅ IMPLEMENTED

**Rationale:**
- Regex fails for nested types like `Array(Tuple(String, UInt64))`
- Go client uses explicit column parsers
- Need proper grammar handling for ClickHouse type syntax

**Type Grammar (Implemented):**
```
type := simple_type | parameterized_type
parameterized_type := type_name "(" type_args ")"
type_args := type | type "," type_args
simple_type := "String" | "UInt8" | "Int32" | ...
```

**Verification:**
```ruby
# Tested and working
parser = ClickhouseRuby::Types::Parser.new
parser.parse('Array(Tuple(String, UInt64))')
# => { type: 'Array', args: [{ type: 'Tuple', args: [...] }] }
```

### 3. Error Handling First ✅ IMPLEMENTED

**Principles (All Applied):**
1. ✅ Always check HTTP status before parsing response
2. ✅ Never silently ignore errors
3. ✅ Provide actionable error messages with context
4. ✅ Distinguish HTTP errors from database errors

### 4. PREWHERE Support 🔜 DEFERRED TO v0.2.0

**Planned Implementation:**
- Extend Arel with `Prewhere` node type
- Add `prewhere` scope method to models
- Generate: `SELECT * FROM t PREWHERE x WHERE y`

### 5. Connection Pooling via HTTP Keep-Alive ✅ IMPLEMENTED

**Strategy (Implemented):**
- Thread-safe connection pool with Queue
- Configurable pool size and timeouts
- Health checks before returning connections

## Architecture - Implementation Status

### Module Structure ✅ IMPLEMENTED

```
lib/
├── chruby.rb                      ✅ Main entry point
├── chruby/
│   ├── version.rb                 ✅
│   ├── configuration.rb           ✅ Global config
│   ├── client.rb                  ✅ HTTP client wrapper
│   ├── connection.rb              ✅ Connection management
│   ├── connection_pool.rb         ✅ Pool implementation
│   ├── result.rb                  ✅ Query result wrapper
│   ├── errors.rb                  ✅ Exception hierarchy
│   ├── types/                     ✅ Type system (14 files)
│   │   ├── base.rb                ✅
│   │   ├── parser.rb              ✅ AST type parser
│   │   ├── registry.rb            ✅ Type registration
│   │   ├── integer.rb             ✅
│   │   ├── float.rb               ✅
│   │   ├── string.rb              ✅
│   │   ├── date_time.rb           ✅
│   │   ├── uuid.rb                ✅
│   │   ├── boolean.rb             ✅
│   │   ├── array.rb               ✅
│   │   ├── map.rb                 ✅
│   │   ├── tuple.rb               ✅
│   │   ├── nullable.rb            ✅
│   │   └── low_cardinality.rb     ✅
│   └── active_record/             ✅ AR integration
│       ├── connection_adapter.rb  ✅
│       ├── arel_visitor.rb        ✅
│       ├── schema_statements.rb   ✅
│       └── railtie.rb             ✅
```

**Deferred to v0.2.0+:**
- `query/builder.rb`, `select.rb`, `insert.rb` - Query building DSL
- `active_record/schema_creation.rb` - CREATE statements DSL
- `active_record/schema_dumper.rb` - Schema export
- `active_record/migration.rb` - Migration DSL
- `active_record/model_extensions.rb` - PREWHERE, FINAL, SAMPLE

### Error Hierarchy ✅ IMPLEMENTED

```
ClickhouseRuby::Error < StandardError
├── ConnectionError < Error           ✅
│   ├── ConnectionNotEstablished     ✅
│   ├── ConnectionTimeout            ✅
│   └── SSLError                     ✅
├── QueryError < Error               ✅
│   ├── StatementInvalid             ✅
│   ├── SyntaxError                  ✅
│   ├── QueryTimeout                 ✅
│   ├── UnknownTable                 ✅
│   ├── UnknownColumn                ✅
│   └── UnknownDatabase              ✅
├── TypeCastError < Error            ✅
├── ConfigurationError < Error       ✅
├── PoolError < Error                ✅
│   ├── PoolExhausted                ✅
│   └── PoolTimeout                  ✅
```

### Type System Design ✅ IMPLEMENTED

```ruby
module ClickhouseRuby
  module Types
    class Registry
      def register(name, type_class)  # ✅
      def lookup(type_string)         # ✅
      def register_defaults           # ✅
    end

    class Parser
      def parse(type_string)          # ✅ AST-based
    end

    class Base
      def cast(value)                 # ✅ Ruby → ClickHouse
      def deserialize(value)          # ✅ ClickHouse → Ruby
      def serialize(value)            # ✅ Ruby → SQL literal
    end
  end
end
```

## Performance Targets

| Metric | Target | Status |
|--------|--------|--------|
| Bulk insert throughput | 100K+ rows/second | ⏳ Needs benchmarking |
| Query latency overhead | <10ms vs raw HTTP | ⏳ Needs benchmarking |
| Connection pool efficiency | O(1) checkout/checkin | ✅ Implemented |
| Memory streaming | Handle 1M+ row results | 🔜 v0.2.0 |

## MVP Feature Set (v0.1.0) - Status

Based on R&D findings, MVP must fix critical pain points:

### Must Have ✅ ALL COMPLETE
1. ✅ **Robust error handling** - No silent failures
2. ✅ **SSL enabled by default** - Security first
3. ✅ **AST-based type parser** - Fix nested type bugs
4. ✅ **JSONEachRow bulk insert** - 5x performance
5. ✅ **Basic SELECT/INSERT** - Core functionality

### Should Have - Partial
1. 🔜 PREWHERE support - v0.2.0
2. ✅ INSERT with SETTINGS
3. ✅ Connection pooling
4. 🔜 HTTP compression - v0.2.0

### Nice to Have - Deferred
1. 🔜 Streaming results - v0.2.0
2. 🔜 Async operations - v1.0.0
3. 🔜 Progress callbacks - v1.0.0

## References

- [clickhouse-go v2](https://github.com/ClickHouse/clickhouse-go)
- [clickhouse-activerecord](https://github.com/PNixx/clickhouse-activerecord)
- [Rails ActiveRecord Adapters](https://github.com/rails/rails/tree/main/activerecord/lib/active_record/connection_adapters)
- [ClickHouse HTTP Interface](https://clickhouse.com/docs/en/interfaces/http)
