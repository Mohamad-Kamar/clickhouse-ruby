# Phase 2 Deep Research: Complete Summary

**Status:** ✅ Research Complete - Ready for Implementation
**Date:** February 2, 2026
**Total Documentation:** 9 features, 117KB of specifications

---

## Executive Summary

Deep research completed for all 9 Phase 2 features. Each feature is fully documented with:
- Comprehensive research findings (ClickHouse behavior, edge cases, gotchas)
- Best practices from industry clients (Go, Python)
- Ralph loop implementation specs with exact proof commands
- Code patterns, file locations, and test scenarios
- Complete SQL examples and integration patterns

**Result:** Self-contained feature files ready for independent ralph-loop implementation.

---

## Features Documented

### Batch 1: Type System (Standalone)
**Status:** 2/2 documented ✓

#### [Enum Type](./features/enum_type.md)
- Enum8 (256 values) and Enum16 (65K values) support
- Value-to-integer bidirectional mapping
- Parser handles quoted values with escaping
- Test: Round-trip INSERT/SELECT with enum validation

**Key Gotcha:** Enum values must be predefined; cannot insert unknown values

#### [Decimal Type](./features/decimal_type.md)
- Decimal(P,S) with 1-76 precision
- BigDecimal for arbitrary precision in Ruby
- Auto-mapping to Decimal32/64/128/256 based on precision
- Validation of P/S constraints before serialization

**Key Gotcha:** Scale cannot exceed precision; precision limited by type (Decimal32 max 9 digits)

---

### Batch 2: Client Enhancements (Core Reliability)
**Status:** 3/3 documented ✓

#### [HTTP Compression](./features/http_compression.md)
- gzip compression with built-in Zlib (zero external deps)
- Request: `Content-Encoding: gzip` header + compressed body
- Response: Auto-decompression on `Content-Encoding: gzip`
- Query param: `enable_http_compression=1`

**Key Gotcha:** Compression adds CPU overhead; only beneficial for large payloads (>1MB)

#### [Retry Logic](./features/retry_logic.md)
- Exponential backoff: `delay = initial × (multiplier ^ attempt)`
- Equal jitter: `delay/2 + random(0, delay/2)` (gRPC standard)
- Retriable: ConnectionError, Timeout, HTTP 5xx/429
- Non-retriable: QueryError (syntax), HTTP 4xx

**Key Gotcha:** INSERT is not idempotent; use query_id or async_insert for safety

#### [Result Streaming](./features/streaming.md)
- Memory-efficient with Enumerable + lazy evaluation
- Uses JSONEachRow format (one JSON per line)
- Client.stream_execute(sql) yields or returns Enumerator
- Memory constant regardless of result size

**Key Gotcha:** Cannot use with FINAL or aggregate functions; SELECT * only

---

### Batch 3: ActiveRecord Query Extensions (Most Requested)
**Status:** 4/4 documented ✓

#### [PREWHERE Support](./features/prewhere.md)
- Query optimization: Filter before reading all columns
- SQL: `SELECT * FROM t PREWHERE col > 100 WHERE status = 'active'`
- Method: `Model.prewhere(conditions).where(...)`
- Auto-optimized by ClickHouse when optimize_move_to_prewhere = 1

**Key Gotcha:** Doesn't work with multiple JOINs; move to subquery if needed

#### [FINAL Modifier](./features/final.md)
- Deduplication at query time (merge during query execution)
- For ReplacingMergeTree/CollapsingMergeTree tables
- SQL: `SELECT * FROM t FINAL WHERE ...`
- Method: `Model.final.where(...)`

**Key Gotcha:** Performance cost (merges data during query); use for accuracy, not speed

#### [SAMPLE Clause](./features/sample.md)
- Approximate queries for large datasets
- Fractional: `SAMPLE 0.1` (10% of data)
- Absolute: `SAMPLE 10000` (at least 10K rows)
- Offset: `SAMPLE 0.1 OFFSET 0.5` (skip 50%, take 10%)
- Method: `Model.sample(0.1).where(...)`

**Key Gotcha:** Requires `SAMPLE BY` clause on table; results need manual adjustment for counts

#### [SETTINGS DSL](./features/settings_dsl.md)
- Per-query settings: `SETTINGS max_execution_time = 60`
- Method: `Model.settings(max_threads: 4).where(...)`
- Appends SETTINGS at end of SQL
- Common: max_execution_time, max_rows_to_read, async_insert

**Key Gotcha:** SETTINGS must be at end of query; unknown settings cause ClickHouse errors

---

## Research Highlights

### ClickHouse-Specific Behaviors

1. **Type System**
   - Enum stores numeric, displays string
   - Decimal uses variable-size storage (32/64/128/256 bits)
   - All types support NULL via Nullable() wrapper

2. **Query Optimization**
   - PREWHERE automatically optimized (set optimize_move_to_prewhere = 1)
   - FINAL requires specific settings when combined with PREWHERE
   - SAMPLE requires table created with SAMPLE BY expression

3. **Mutation Semantics**
   - DELETE/UPDATE are mutations (ALTER TABLE syntax)
   - Retry with query_id to prevent duplicates
   - mutations_sync setting controls when operation completes

### Common Patterns Across Implementations

**Go (clickhouse-go)**
- Direct SQL manipulation (no helper methods for PREWHERE, FINAL)
- Compression handled transparently
- Retry handled by caller

**Python (clickhouse-driver)**
- Similar to Go (SQL-centric)
- Streaming via iterator pattern
- Settings passed as parameters

**Ruby (ClickhouseRuby)**
- ActiveRecord-style chainable methods
- Explicit query builders for clarity
- Settings encapsulated in relation

### Best Practices Distilled

1. **Type System**
   - Use Enum for low-cardinality string columns
   - Use Decimal for financial data (not Float)
   - Always validate input before casting

2. **Connection Management**
   - Implement exponential backoff with jitter (not linear)
   - Don't retry QueryError (syntax errors)
   - Use query_id for operation deduplication

3. **Query Optimization**
   - Use PREWHERE for date/time/enum filters (high selectivity)
   - Use WHERE for complex conditions (applied after blocks eliminated)
   - Let auto-optimization work; explicit PREWHERE rarely needed

4. **Result Handling**
   - Stream large results (>100MB)
   - Use JSONEachRow format for streaming
   - Never load full result in memory

---

## Implementation Strategy

### Recommended Order (24-32 hours total)

**Phase 2.1 - Types (4-6 hours)**
1. Enum Type (2-3 hrs)
2. Decimal Type (2-3 hrs)

**Phase 2.2 - Client (11-15 hours)**
3. HTTP Compression (3-4 hrs)
4. Retry Logic (4-5 hrs)
5. Streaming (4-5 hrs)

**Phase 2.3 - ActiveRecord (9-11 hours)**
6. PREWHERE (3-4 hrs)
7. FINAL (1-2 hrs)
8. SAMPLE (2-3 hrs)
9. SETTINGS (2-3 hrs)

### Quality Gates

Each feature must pass:
- [ ] Unit tests: `bundle exec rake spec_unit`
- [ ] Integration tests: `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rake spec_integration`
- [ ] Lint: `bundle exec rake rubocop`
- [ ] Coverage: 80%+ minimum
- [ ] All proof commands in Ralph loop checklist

### Ralph Loop Execution

For each feature:
1. Open feature doc (e.g., `docs/features/enum_type.md`)
2. Read Guardrails section
3. Create test file with scenarios from "Test Scenarios"
4. Run Ralph loop:
   - [ ] Checkbox 1: Implement → Run proof → Pass ✓
   - [ ] Checkbox 2: Implement → Run proof → Pass ✓
   - ... repeat ...
5. All checkboxes pass → Feature complete

---

## Documentation Structure

```
docs/features/
├── README.md                    ← Start here!
├── enum_type.md               ← Batch 1
├── decimal_type.md            ← Batch 1
├── http_compression.md        ← Batch 2
├── retry_logic.md             ← Batch 2
├── streaming.md               ← Batch 2
├── prewhere.md                ← Batch 3
├── final.md                   ← Batch 3
├── sample.md                  ← Batch 3
└── settings_dsl.md            ← Batch 3
```

**Each file contains:**
- Research Summary (what, why, how)
- Gotchas & Edge Cases (what could go wrong)
- Best Practices (when/how to use)
- Implementation Details (where, code patterns)
- Ralph Loop Checklist (testable outcomes)
- Test Scenarios (exact test examples)
- References (ClickHouse docs, examples)

---

## Key Findings by Category

### Type System Research
- Enum: Fixed set of string values, stored as integers
- Decimal: Variable precision, use BigDecimal in Ruby
- Both: Required validation in Ruby layer

### Compression Research
- gzip: Built-in Zlib, ~5-10x size reduction for JSON
- lz4: ClickHouse default, would need external gem (skip v0.2.0)
- Overhead: CPU cost only beneficial for large payloads

### Retry Strategy Research
- Exponential backoff prevents thundering herd
- Equal jitter: balanced predictability (1.6x multiplier recommended)
- gRPC standard: initial=1s, multiplier=1.6, max=120s

### Query Extensions Research
- PREWHERE: Automatic optimization works well (explicit rarely needed)
- FINAL: Performance cost high; use for accuracy, not reporting
- SAMPLE: Requires schema support (SAMPLE BY); results approximate
- SETTINGS: Powerful but must appear at query end

---

## No Additional Research Needed

All features have been researched at depth:
- ✅ ClickHouse official documentation reviewed
- ✅ Go/Python implementations analyzed
- ✅ Edge cases and gotchas documented
- ✅ Best practices distilled and explained
- ✅ SQL syntax and behavior verified
- ✅ Ruby integration patterns established
- ✅ Test strategies and examples provided

**You're ready to start implementation!**

---

## Next Step

1. **Open:** `/docs/features/README.md` (quick navigation guide)
2. **Choose:** Start with Enum Type (Batch 1) - no dependencies
3. **Read:** `enum_type.md` - full feature specification
4. **Implement:** Follow Ralph loop checklist
5. **Verify:** All proof commands pass
6. **Move:** To next feature (Decimal Type)

---

## Questions to Answer During Implementation

If you get stuck, reference the feature doc:
- **"What does this do?"** → Research Summary
- **"What breaks easily?"** → Gotchas & Edge Cases
- **"How do I use it?"** → Best Practices
- **"Where do I code it?"** → Implementation Details
- **"How do I test it?"** → Test Scenarios
- **"Did I miss anything?"** → Ralph Loop Checklist

**All answers are in the feature docs. No external research needed.**

---

**Status:** Research Complete ✅
**Documentation:** 117KB across 10 files
**Ready for:** Ralph-loop implementation

**Start with:** [docs/features/enum_type.md](./features/enum_type.md)
