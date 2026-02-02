# Phase 2 Features: Quick Reference Card

## The 9 Features at a Glance

### Batch 1: Types (No dependencies)

**Enum Type** | `lib/clickhouse_ruby/types/enum.rb`
- Parse: `Enum8('active' = 1, 'inactive' = 2)`
- Ruby: Use String, validate against possible_values
- Test: Unit test + integration round-trip

**Decimal Type** | `lib/clickhouse_ruby/types/decimal.rb`
- Parse: `Decimal(18, 4)` (precision, scale)
- Ruby: Use BigDecimal for arbitrary precision
- Test: Unit test + integration round-trip

---

### Batch 2: Client (Core improvements)

**HTTP Compression** | `lib/clickhouse_ruby/connection.rb`
- Add: `compression: 'gzip'` config option
- Header: `Content-Encoding: gzip` (request)
- Header: `Accept-Encoding: gzip` (response)
- Lib: Zlib (built-in, zero dependencies)

**Retry Logic** | `lib/clickhouse_ruby/retry_handler.rb`
- Formula: `delay = initial × (1.6 ^ attempt)` capped at max
- Jitter: `delay/2 + random(0, delay/2)`
- Retriable: ConnectionError, Timeout, HTTP 5xx/429
- Non-retriable: QueryError (syntax), HTTP 4xx

**Result Streaming** | `lib/clickhouse_ruby/streaming_result.rb`
- Format: JSONEachRow (one JSON per line)
- Method: `client.stream_execute(sql) { |row| ... }`
- Memory: Constant, yields one row at a time
- Pattern: Enumerable + lazy evaluation

---

### Batch 3: ActiveRecord (Query extensions)

**PREWHERE** | `lib/clickhouse_ruby/active_record/relation_extensions.rb`
- SQL: `SELECT ... FROM ... PREWHERE col > val WHERE ...`
- Method: `Model.prewhere(status: 'active').where(price: 100..200)`
- Position: Before WHERE, after FROM/FINAL/SAMPLE
- Limitation: Doesn't work with multiple JOINs

**FINAL** | `lib/clickhouse_ruby/active_record/relation_extensions.rb`
- SQL: `SELECT ... FROM table FINAL WHERE ...`
- Method: `Model.final.where(user_id: 123)`
- Use: ReplacingMergeTree deduplication
- Cost: Performance (merges during query)

**SAMPLE** | `lib/clickhouse_ruby/active_record/relation_extensions.rb`
- SQL: `SELECT ... FROM table SAMPLE 0.1 OFFSET 0.5 WHERE ...`
- Method: `Model.sample(0.1).where(status: 'active')`
- Types: Fractional (0.1), Absolute (10000), Offset
- Results: Approximate, may need manual adjustment

**SETTINGS** | `lib/clickhouse_ruby/active_record/relation_extensions.rb`
- SQL: `SELECT ... WHERE ... SETTINGS max_threads = 4, final = 1`
- Method: `Model.settings(max_threads: 4).where(active: true)`
- Position: At very end of query
- Types: Integer, Float, String (quoted), Boolean (0/1)

---

## Quick Checklist: Am I Ready?

- [ ] Opened `/docs/features/README.md`
- [ ] Read "Implementation Order" section
- [ ] Opened first feature file: `enum_type.md`
- [ ] Read "Guardrails" section
- [ ] Read "Research Summary" section
- [ ] Created test file from "Test Scenarios"
- [ ] Starting Ralph loop...

---

## Ralph Loop Template

```
Feature: Enum Type

Guardails:
- Don't change: Existing type system architecture
- Must keep: Type registry pattern, parser compatibility

Checklist:
[ ] Enum class exists at lib/clickhouse_ruby/types/enum.rb
    prove: ruby -r./lib/clickhouse_ruby -e "ClickhouseRuby::Types::Enum"
[ ] Parser handles Enum('a','b') syntax
    prove: bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "parses"
[ ] cast() converts String to valid enum value
    prove: bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "cast"
... more checkboxes ...
```

**For each [ ]:**
1. Implement code
2. Run prove command
3. Check if PASS/FAIL
4. Mark [✓] if PASS, continue if FAIL
5. Debug and repeat

---

## File Locations Reference

```
lib/clickhouse_ruby/
├── types/
│   ├── enum.rb                    ← Enum Type
│   ├── decimal.rb                 ← Decimal Type
│   └── registry.rb                ← Register types
├── connection.rb                  ← Compression
├── retry_handler.rb               ← Retry Logic (new)
├── streaming_result.rb            ← Streaming (new)
├── client.rb                      ← Update for all
└── active_record/
    ├── relation_extensions.rb     ← All AR features (new)
    └── arel_visitor.rb            ← SQL generation

spec/
├── unit/
│   ├── clickhouse_ruby/types/
│   │   ├── enum_spec.rb           ← Enum tests
│   │   ├── decimal_spec.rb        ← Decimal tests
│   │   └── ...
│   └── clickhouse_ruby/
│       ├── retry_handler_spec.rb  ← Retry tests
│       ├── streaming_result_spec.rb ← Streaming tests
│       └── ...
└── integration/
    ├── enum_spec.rb               ← Enum integration
    ├── decimal_spec.rb            ← Decimal integration
    ├── compression_spec.rb        ← Compression integration
    └── ...
```

---

## Common Commands

```bash
# Run specific test
bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "cast"

# Run all unit tests
bundle exec rake spec_unit

# Run all integration tests
CLICKHOUSE_TEST_INTEGRATION=true bundle exec rake spec_integration

# Lint check
bundle exec rake rubocop

# Full check (tests + lint)
bundle exec rake check

# View coverage
open coverage/index.html
```

---

## Feature Dependencies

```
Batch 1: Standalone Types
├─ Enum Type
└─ Decimal Type

Batch 2: Client Core
├─ HTTP Compression (independent)
├─ Retry Logic (independent)
└─ Result Streaming (independent)

Batch 3: ActiveRecord Query (share RelationExtensions)
├─ PREWHERE
├─ FINAL
├─ SAMPLE
└─ SETTINGS DSL
```

**Note:** Can implement Batch 1 & 2 in any order. Batch 3 shares infrastructure.

---

## Key Gotchas (Stop Here First!)

### Enum Type
- Values must be predefined in schema
- Cannot insert unknown values
- Ordering is numeric (1, 2, 3) not alphabetical

### Decimal Type
- Scale cannot exceed precision
- Decimal32 max 9 digits, Decimal64 max 18 digits
- Use BigDecimal in Ruby (not Float)

### HTTP Compression
- Overhead for small payloads (<1MB)
- Uses Zlib (built-in, no external gems)
- Must set `enable_http_compression=1` in query params

### Retry Logic
- INSERT not idempotent by default
- Use query_id or async_insert for safety
- Don't retry QueryError (syntax errors)

### Streaming
- Cannot use with FINAL
- Cannot use with aggregate functions
- Only SELECT * works

### PREWHERE
- Doesn't work with multiple JOINs
- Requires MergeTree family tables
- Auto-optimization works well (explicit rarely needed)

### FINAL
- Performance cost is high
- Use for accuracy, not speed
- Requires specific table engines

### SAMPLE
- Requires `SAMPLE BY` clause on table creation
- Results are approximate
- Counts need manual adjustment or `_sample_factor`

### SETTINGS
- Must be at END of query
- Unknown settings cause ClickHouse errors
- Boolean values as 0/1, not true/false

---

## Start Here

1. **Read this file** (you are here)
2. **Open:** `docs/features/README.md`
3. **Choose:** Batch 1, Feature 1 (Enum Type)
4. **Open:** `docs/features/enum_type.md`
5. **Start:** Ralph loop (follow the checklist)

---

**You have everything needed to implement all 9 features.**

No external research required. All information is in the feature docs.

**Go build it! 🚀**
