# Phase 2 Features: Complete Research Documentation

This directory contains comprehensive research and Ralph loop implementation specs for ClickhouseRuby v0.2.0 features.

## Quick Start

Each feature file is **self-contained** and can be implemented independently. Start with any feature by:

1. Open the feature file (e.g., `enum_type.md`)
2. Follow the **Ralph Loop Checklist** section
3. Run proof commands to verify each checkbox
4. All checkboxes pass = feature complete

## Implementation Order

### Batch 1: Types (Standalone, ~1-2 days each)
Start here - no dependencies on other features:
- [`enum_type.md`](./enum_type.md) - Enum8/Enum16 support
- [`decimal_type.md`](./decimal_type.md) - Decimal(P,S) support

### Batch 2: Client Enhancements (~2-3 days each)
Core reliability and performance improvements:
- [`http_compression.md`](./http_compression.md) - gzip compression
- [`retry_logic.md`](./retry_logic.md) - Exponential backoff
- [`streaming.md`](./streaming.md) - Memory-efficient results

### Batch 3: ActiveRecord Query Extensions (~1-2 days each)
Most-requested query features:
- [`prewhere.md`](./prewhere.md) - PREWHERE clause (query optimization)
- [`final.md`](./final.md) - FINAL modifier (deduplication)
- [`sample.md`](./sample.md) - SAMPLE clause (approximate queries)
- [`settings_dsl.md`](./settings_dsl.md) - Per-query SETTINGS

## File Sizes & Content

| Feature | Size | Type | Complexity |
|---------|------|------|------------|
| enum_type | 9.8KB | Type | Medium |
| decimal_type | 11.8KB | Type | Medium |
| http_compression | 12.5KB | Client | Low |
| retry_logic | 14.2KB | Client | High |
| streaming | 14.6KB | Client | High |
| prewhere | 13.4KB | ActiveRecord | Medium |
| final | 12.7KB | ActiveRecord | Low |
| sample | 14.3KB | ActiveRecord | Medium |
| settings_dsl | 14.2KB | ActiveRecord | Low |

**Total:** ~117KB of research and implementation guidance

## What Each File Contains

### 1. Research Summary
- Deep research findings with sources
- ClickHouse engine details
- Comparison with Go/Python implementations
- SQL syntax variations

### 2. Gotchas & Edge Cases
- Common mistakes when implementing
- Error conditions to handle
- Performance pitfalls
- Interaction with other features

### 3. Best Practices
- When to use the feature
- Common patterns from industry
- Configuration recommendations
- Performance optimization tips

### 4. Implementation Details
- Exact file locations
- Code patterns and templates
- Class structure recommendations
- Integration points with existing code

### 5. Ralph Loop Checklist
- 8-12 testable outcomes per feature
- Proof commands for verification
- Exact `bundle exec rspec` commands
- Integration test requirements

### 6. Test Scenarios
- Unit test examples
- Integration test examples
- Parametric test patterns
- Edge case coverage

## Ralph Loop Methodology

Each feature follows this pattern:

```
┌─────────────────────────────────────────┐
│ 1. Read feature file (Guardrails)       │
├─────────────────────────────────────────┤
│ 2. Understand research & gotchas         │
├─────────────────────────────────────────┤
│ 3. Run Ralph Loop (iterate):            │
│   a) Implement code                     │
│   b) Run proof command                  │
│   c) Mark checkbox ✓                    │
│   d) Next checkbox                      │
├─────────────────────────────────────────┤
│ 4. All checkboxes ✓ → Feature complete  │
└─────────────────────────────────────────┘
```

### Proof Commands Pattern

Every checkbox has a `**prove:**` command that:
- Runs a specific test or command
- Returns **pass/fail** (binary outcome)
- No manual judgment needed
- Examples:
  ```bash
  bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "parses"
  bundle exec rake spec_unit
  bundle exec rake rubocop
  ```

## Implementation Guidelines

### 1. Test-First Approach
- Create spec files first (tests are in the docs)
- Implement minimum code to pass tests
- Run proof command to verify

### 2. Isolated Features
- Each feature is independent
- Can be implemented in any order
- No cross-feature dependencies in Batch 1 & 2
- Batch 3 features share `RelationExtensions` module

### 3. No Over-Engineering
- Implement exactly what's specified
- Don't add extra features
- Don't "improve" existing code
- Follow existing patterns

### 4. Documentation Quality
- Each feature doc is complete
- No "research further" sections
- Gotchas are explicitly listed
- Best practices are clear

## Common Patterns Across Features

### Type Features (Enum, Decimal)
```ruby
# Pattern location: lib/clickhouse_ruby/types/your_type.rb
class YourType < Base
  def cast(value)       # Ruby → ClickHouse
  def deserialize(val)  # Response → Ruby
  def serialize(val)    # Ruby → SQL literal
  def nullable?         # Boolean
  def to_s              # Type string
end

# Register in lib/clickhouse_ruby/types/registry.rb
register('YourType', YourType)
```

### Client Features (Compression, Retry, Streaming)
```ruby
# Modifications to:
# - lib/clickhouse_ruby/configuration.rb (add options)
# - lib/clickhouse_ruby/connection.rb (implement)
# - lib/clickhouse_ruby/client.rb (expose methods)

# Pattern: Minimal changes, maximum leverage of existing code
```

### ActiveRecord Features (PREWHERE, FINAL, SAMPLE, SETTINGS)
```ruby
# All share RelationExtensions module at:
# lib/clickhouse_ruby/active_record/relation_extensions.rb

# Pattern:
def method_name(opts = :chain)
  if opts == :chain
    MethodNameChain.new(spawn)
  else
    spawn.method_name!(opts)
  end
end

# Chain into Arel visitor for SQL generation
```

## Verification Checklist

Before moving to next feature:
- [ ] All checkboxes marked ✓
- [ ] `bundle exec rake spec_unit` passes
- [ ] `bundle exec rake rubocop` passes (no lint errors)
- [ ] Integration test passes (if applicable)
- [ ] No existing tests broken

## Performance Expectations

| Feature | Impl Time | Test Coverage | Priority |
|---------|-----------|---------------|----------|
| Enum | 2-3 hrs | 90%+ | High |
| Decimal | 2-3 hrs | 90%+ | High |
| Compression | 3-4 hrs | 85%+ | Medium |
| Retry | 4-5 hrs | 90%+ | High |
| Streaming | 4-5 hrs | 85%+ | Medium |
| PREWHERE | 3-4 hrs | 85%+ | High |
| FINAL | 1-2 hrs | 80%+ | Medium |
| SAMPLE | 2-3 hrs | 80%+ | Medium |
| SETTINGS | 2-3 hrs | 80%+ | Low |

**Total Estimate:** 24-32 implementation hours

## Getting Unstuck

### Issue: Test fails, but implementation looks correct

1. **Check the proof command:** Exact test name match?
2. **Re-read Gotchas section:** Any edge cases missed?
3. **Look at test scenario:** Example tests in feature doc
4. **Compare with similar code:** Look at existing types or methods

### Issue: SQL generation wrong

1. **Print the SQL:** Add debug output to see generated SQL
2. **Compare with Research Summary:** Examples show expected SQL
3. **Check clause ordering:** SQL order matters for ClickHouse
4. **Verify Arel visitor:** Method override correct?

### Issue: Integration test fails

1. **Check table engine:** Some features only work on MergeTree
2. **Verify test setup:** ClickHouse running? Table created?
3. **Check ClickHouse version:** Some features new in recent versions
4. **Review error message:** ClickHouse errors are detailed

## References & Resources

### ClickHouse Documentation
- [ClickHouse SQL Reference](https://clickhouse.com/docs/en/sql-reference/)
- [Data Types](https://clickhouse.com/docs/en/sql-reference/data-types/)
- [Query Optimization](https://clickhouse.com/docs/en/sql-reference/statements/select/prewhere)

### Ruby/Rails Resources
- [ActiveRecord Query Interface](https://guides.rubyonrails.org/active_record_querying.html)
- [Arel Library](https://github.com/rails/arel)
- [RSpec Testing](https://rspec.info/)

### ClickhouseRuby Project
- Architecture: See [/docs/MVP.md](../MVP.md)
- Existing patterns: Look at [lib/clickhouse_ruby/types/](../../lib/clickhouse_ruby/types/)
- Test patterns: See [spec/unit/](../../spec/unit/)

## Next Steps

1. **Choose first feature** from Batch 1 (Enum or Decimal)
2. **Open the feature file** (e.g., `enum_type.md`)
3. **Read Guardrails section** (understand constraints)
4. **Read Research Summary** (understand what you're building)
5. **Create test file** (from Test Scenarios section)
6. **Implement code** (from Implementation Details section)
7. **Run Ralph Loop** (iterate through checklist)
8. **Move to next feature** (when all ✓)

## Questions?

Refer to the specific feature file's:
- Research Summary → "What is this feature?"
- Gotchas & Edge Cases → "What could go wrong?"
- Best Practices → "How should I use this?"
- Implementation Details → "How do I code it?"
- Test Scenarios → "How do I test it?"

Each feature is designed to be **completely self-contained** with all information needed for implementation.

---

**Status:** All 9 features researched and documented. Ready for implementation.

Start with [`enum_type.md`](./enum_type.md)!
