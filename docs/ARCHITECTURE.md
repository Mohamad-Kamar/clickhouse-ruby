# ClickhouseRuby Architecture Document

> **Last Updated:** 2026-01-31
> **Status:** v0.1.0 Implementation Complete

## Overview

ClickhouseRuby is a Ruby/ActiveRecord integration for ClickHouse that prioritizes:
- **Reliability** - No silent failures, clear error messages
- **Performance** - Bulk operations, connection pooling
- **Developer Experience** - Intuitive API, easy onboarding
- **OLAP-first** - Designed for analytics, not CRUD

## Gem Structure Decision

### Decision: Monolithic Gem with Clear Internal Layers ✅ IMPLEMENTED

**Rationale:**
- Simpler dependency management for users
- Consistent versioning across components
- Easier testing and maintenance
- Can extract layers later if needed

## Module Hierarchy

### Implemented (v0.1.0)

```
ClickhouseRuby (main namespace)
├── VERSION                    ✅
├── Configuration              ✅ Global settings
├── Client                     ✅ Low-level HTTP client
├── Connection                 ✅ Single connection wrapper
├── ConnectionPool             ✅ Pool management
├── Result                     ✅ Query result container
│
├── Types                      ✅ Type system
│   ├── Registry               ✅ Type lookup and registration
│   ├── Parser                 ✅ AST-based type parser
│   ├── Base                   ✅ Abstract base type
│   ├── Integer                ✅ UInt8-256, Int8-256
│   ├── Float                  ✅ Float32, Float64
│   ├── String                 ✅ String, FixedString
│   ├── DateTime               ✅ Date, DateTime, DateTime64
│   ├── UUID                   ✅ UUID
│   ├── Boolean                ✅ Bool
│   ├── Array                  ✅ Array(T)
│   ├── Map                    ✅ Map(K, V)
│   ├── Tuple                  ✅ Tuple(T1, T2, ...)
│   ├── Nullable               ✅ Nullable(T)
│   └── LowCardinality         ✅ LowCardinality(T)
│
├── Errors                     ✅ Exception hierarchy
│   ├── Error                  ✅ Base error
│   ├── ConnectionError        ✅ Connection issues
│   ├── QueryError             ✅ Query execution issues
│   ├── TypeCastError          ✅ Type conversion issues
│   └── ConfigurationError     ✅
│
└── ActiveRecord               ✅ Rails integration
    ├── ConnectionAdapter      ✅ AR adapter
    ├── ArelVisitor            ✅ SQL generation
    ├── SchemaStatements       ✅ DDL operations
    └── Railtie                ✅ Rails integration
```

### Planned for Future Versions

```
ClickhouseRuby (additions)
├── StreamingResult            🔜 v0.2.0 - Large result streaming
│
├── Types (additions)
│   ├── Decimal                🔜 v0.2.0 - Decimal(P, S)
│   └── Enum                   🔜 v0.2.0 - Enum8, Enum16
│
├── Query                      🔜 v0.2.0+ - Query building
│   ├── Builder                - Fluent query construction
│   ├── Select                 - SELECT statement
│   ├── Insert                 - INSERT statement
│   └── Settings               - Query settings
│
└── ActiveRecord (additions)
    ├── SchemaCreation         🔜 v0.2.0 - CREATE statements
    ├── SchemaDumper           🔜 v0.2.0 - Schema export
    ├── TableDefinition        🔜 v0.2.0 - Migration DSL
    ├── Migration              🔜 v0.2.0 - Migration support
    └── ModelExtensions        🔜 v0.2.0 - PREWHERE, FINAL, etc.
```

## File Organization

### Actual Implementation (v0.1.0)

```
chruby/
├── lib/
│   ├── chruby.rb                           ✅ Main entry, autoloading
│   └── chruby/
│       ├── version.rb                      ✅
│       ├── configuration.rb                ✅
│       ├── client.rb                       ✅
│       ├── connection.rb                   ✅
│       ├── connection_pool.rb              ✅
│       ├── result.rb                       ✅
│       ├── errors.rb                       ✅
│       │
│       ├── types/
│       │   ├── parser.rb                   ✅ AST-based (not regex!)
│       │   ├── registry.rb                 ✅
│       │   ├── base.rb                     ✅
│       │   ├── integer.rb                  ✅
│       │   ├── float.rb                    ✅
│       │   ├── string.rb                   ✅
│       │   ├── date_time.rb                ✅
│       │   ├── uuid.rb                     ✅
│       │   ├── boolean.rb                  ✅
│       │   ├── array.rb                    ✅
│       │   ├── map.rb                      ✅
│       │   ├── tuple.rb                    ✅
│       │   ├── nullable.rb                 ✅
│       │   └── low_cardinality.rb          ✅
│       │
│       └── active_record/
│           ├── connection_adapter.rb       ✅
│           ├── arel_visitor.rb             ✅
│           ├── schema_statements.rb        ✅
│           └── railtie.rb                  ✅
│
├── spec/
│   ├── spec_helper.rb                      ✅
│   ├── support/
│   │   └── clickhouse_helper.rb            ✅
│   │
│   ├── unit/
│   │   ├── chruby_spec.rb                  ✅
│   │   └── chruby/
│   │       ├── configuration_spec.rb       ✅
│   │       ├── errors_spec.rb              ✅
│   │       └── types/
│   │           ├── parser_spec.rb          ✅
│   │           ├── registry_spec.rb        ✅
│   │           ├── integer_spec.rb         ✅
│   │           ├── array_spec.rb           ✅
│   │           ├── map_spec.rb             ✅
│   │           ├── tuple_spec.rb           ✅
│   │           └── nullable_spec.rb        ✅
│   │
│   └── integration/
│       ├── connection_spec.rb              ✅
│       ├── error_handling_spec.rb          ✅
│       ├── insert_spec.rb                  ✅
│       └── types_spec.rb                   ✅
│
├── Gemfile                                 ✅
├── chruby.gemspec                          ✅
├── Rakefile                                ✅
├── LICENSE                                 ✅
├── README.md                               ✅
├── CHANGELOG.md                            ✅
└── docker-compose.yml                      ✅
```

## Component Details

### 1. Configuration ✅ IMPLEMENTED

```ruby
module ClickhouseRuby
  class Configuration
    attr_accessor :host, :port, :database, :username, :password
    attr_accessor :ssl, :ssl_verify, :ssl_ca_path
    attr_accessor :read_timeout, :write_timeout, :connect_timeout
    attr_accessor :pool_size, :pool_timeout
    attr_accessor :logger, :log_level
    attr_accessor :default_settings  # ClickHouse query settings

    def initialize
      @host = 'localhost'
      @port = 8123
      @database = 'default'
      @ssl = false
      @ssl_verify = true  # SECURITY: Verify by default!
      @read_timeout = 60
      @write_timeout = 60
      @connect_timeout = 10
      @pool_size = 5
      @pool_timeout = 5
    end
  end
end
```

### 2. Client (HTTP Layer) ✅ IMPLEMENTED

Key implementation detail - **always check HTTP status first**:

```ruby
def handle_response(response, format)
  # CRITICAL: Always check status first! (fixes issue #230)
  unless response.code == '200'
    raise_error_from_response(response)
  end
  parse_response(response, format)
end
```

### 3. Connection Pool ✅ IMPLEMENTED

Thread-safe pool with health checks before returning connections.

### 4. Type Parser (AST-Based) ✅ IMPLEMENTED

Grammar implemented:
```
type := simple_type | parameterized_type
parameterized_type := identifier "(" type_list ")"
type_list := type ("," type)*
simple_type := identifier
```

Verified working with nested types:
```ruby
parser.parse('Array(Tuple(String, UInt64))')
# => { type: 'Array', args: [{ type: 'Tuple', args: [...] }] }
```

### 5. Error Handling Strategy ✅ IMPLEMENTED

Full hierarchy with error code mapping:
- `Error` → base class
- `ConnectionError` → connection issues
- `QueryError` → query failures (with code, http_status, sql)
- `TypeCastError` → type conversion failures

Error code mapping to specific exceptions:
- Code 60 → `UnknownTable`
- Code 16 → `UnknownColumn`
- Code 62 → `SyntaxError`
- Code 159 → `QueryTimeout`

## ActiveRecord Integration ✅ IMPLEMENTED

### Connection Adapter

Capabilities properly declared:
```ruby
def supports_ddl_transactions?; false; end
def supports_savepoints?; false; end
def supports_transaction_isolation?; false; end
def supports_insert_returning?; false; end
def supports_foreign_keys?; false; end
```

### Arel Visitor

Converts DELETE/UPDATE to ClickHouse syntax:
```ruby
# DELETE becomes: ALTER TABLE x DELETE WHERE y
# UPDATE becomes: ALTER TABLE x UPDATE col = val WHERE y
```

### Schema Statements

Queries system tables for introspection:
- `system.tables` - list tables
- `system.columns` - list columns
- `system.data_skipping_indices` - list indexes

## Data Flow Diagrams

### Query Execution Flow ✅ IMPLEMENTED

```
User Code
    │
    ▼
Model.where(...) or client.execute(sql)
    │
    ▼
[ActiveRecord: Arel AST → ArelVisitor → SQL]
    │
    ▼
ConnectionAdapter.execute(sql) or Client.execute(sql)
    │
    ▼
ConnectionPool.with_connection
    │
    ▼
HTTP POST to ClickHouse
    │
    ▼
Response (JSON)
    │
    ▼
Error Check (HTTP status + body)  ← CRITICAL: Check first!
    │
    ▼
Type Deserialization
    │
    ▼
Result Object
```

### Bulk Insert Flow ✅ IMPLEMENTED

```
User Code
    │
    ▼
client.insert(table, rows, format: :json_each_row)
    │
    ▼
Build JSONEachRow payload
    │
    ▼
HTTP POST with body
    │
    ▼
ClickHouse processes rows
    │
    ▼
Response verification (check status!)
    │
    ▼
Return result
```

## Security Considerations ✅ ADDRESSED

1. **SSL/TLS**
   - Certificate verification **ON by default** (security fix vs existing gems)
   - Auto-enabled for ports 8443, 443
   - Option to specify custom CA

2. **Authentication**
   - Username/password via X-ClickHouse-User/Key headers

3. **SQL Injection**
   - Proper quoting in Arel visitor

4. **Secrets Management**
   - Passwords not logged

## Performance Considerations ✅ ADDRESSED

1. **Connection Pooling**
   - HTTP keep-alive connections
   - Configurable pool size
   - Health checks

2. **Bulk Operations**
   - JSONEachRow format (5x faster than VALUES)

3. **Compression** 🔜 v0.2.0
   - Not yet implemented

4. **Streaming** 🔜 v0.2.0
   - Not yet implemented

## Implementation Status Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Configuration | ✅ Complete | SSL verify on by default |
| HTTP Client | ✅ Complete | Error handling first |
| Connection Pool | ✅ Complete | Thread-safe |
| Type Parser | ✅ Complete | AST-based, nested types work |
| Type Registry | ✅ Complete | 14 types implemented |
| Error Hierarchy | ✅ Complete | Code mapping included |
| Result Object | ✅ Complete | Enumerable interface |
| AR Adapter | ✅ Complete | Basic CRUD |
| Arel Visitor | ✅ Complete | DELETE/UPDATE syntax |
| Schema Introspection | ✅ Complete | Via system tables |
| Railtie | ✅ Complete | Rails integration |
| Streaming | 🔜 v0.2.0 | Not implemented |
| Compression | 🔜 v0.2.0 | Not implemented |
| PREWHERE | 🔜 v0.2.0 | Not implemented |
| Migration DSL | 🔜 v0.2.0 | Not implemented |
