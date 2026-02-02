# Feature: FINAL Modifier

> **Status:** Not Started
> **Priority:** High (Batch 3)
> **Dependencies:** RelationExtensions module (shared with PREWHERE, SAMPLE, SETTINGS)

---

## Guardrails

- **Don't change:** Existing FROM clause generation, table name handling
- **Must keep:** Chainable, proper SQL position (after table name, before SAMPLE/PREWHERE/WHERE)
- **Definition of done:** All boxes checked + proof commands pass
- **Stop condition:** All checkboxes verified, integration test passes

---

## Research Summary

### What is FINAL?

FINAL forces ClickHouse to merge data at query time, ensuring you see the "final" state of rows in certain table engines:

| Engine | FINAL Behavior |
|--------|----------------|
| **ReplacingMergeTree** | Returns only latest version of each row |
| **CollapsingMergeTree** | Returns collapsed (net) rows |
| **SummingMergeTree** | Returns summed values |
| **AggregatingMergeTree** | Returns merged aggregates |
| **VersionedCollapsingMergeTree** | Returns collapsed with version awareness |

### Why FINAL is Needed

ClickHouse uses eventual consistency - data merges happen in background:

```sql
-- Insert two versions of same row
INSERT INTO users VALUES (1, 'Alice', 1);  -- version 1
INSERT INTO users VALUES (1, 'Alicia', 2); -- version 2

-- Without FINAL: May see both rows!
SELECT * FROM users WHERE id = 1;
-- (1, 'Alice', 1)
-- (1, 'Alicia', 2)

-- With FINAL: Sees only latest
SELECT * FROM users FINAL WHERE id = 1;
-- (1, 'Alicia', 2)
```

### SQL Syntax

```sql
-- In FROM clause
SELECT * FROM table FINAL WHERE ...

-- Via settings
SELECT * FROM table WHERE ... SETTINGS final = 1

-- Session level
SET final = 1;
SELECT * FROM table WHERE ...
```

### Clause Ordering

```sql
SELECT ...
FROM table FINAL      -- FINAL immediately after table name
SAMPLE 0.1            -- Then SAMPLE
PREWHERE expr         -- Then PREWHERE
WHERE expr            -- Then WHERE
...
```

---

## Gotchas & Edge Cases

### 1. Significant Performance Impact
```sql
-- FINAL forces merge during query
-- Can be 2-10x slower than without FINAL

-- For large tables, consider:
-- 1. Force merge offline: OPTIMIZE TABLE ... FINAL
-- 2. Use GROUP BY with sign column for CollapsingMergeTree
-- 3. Accept eventual consistency when possible
```

**Ruby Implementation:** Document performance implications; consider `final!` (bang) method to emphasize cost.

### 2. FINAL with PREWHERE Requires Settings
```sql
-- Without settings, PREWHERE may not work with FINAL
SELECT * FROM table FINAL PREWHERE x > 1;

-- Must enable both settings
SET optimize_move_to_prewhere = 1;
SET optimize_move_to_prewhere_if_final = 1;
```

**Ruby Implementation:** Automatically add these settings when combining `final` with `prewhere`.

### 3. FINAL Reads Additional Columns
```sql
-- FINAL needs version/sign columns to merge
-- Even if not in SELECT, they're read from disk

-- Example: ReplacingMergeTree(version)
SELECT name FROM users FINAL;  -- Also reads 'version' column
```

### 4. FINAL with Distributed Tables
```sql
-- FINAL is applied on each shard independently
-- May still see inconsistencies across shards

-- For true consistency, use:
-- 1. optimize_distributed_group_by_sharding_key
-- 2. distributed_group_by_no_merge
```

### 5. FINAL Cannot Be Disabled Mid-Query
```sql
-- Once FINAL is in query, it applies to whole result
-- Cannot have FINAL for some columns, not others
```

### 6. Incomplete Data with FINAL
```sql
-- With ReplacingMergeTree + is_deleted column
-- FINAL still returns rows where is_deleted = 0 by default

-- To exclude deleted rows, need:
CREATE TABLE t (...) ENGINE = ReplacingMergeTree(version, is_deleted)
-- Then FINAL excludes rows where is_deleted = 1
```

---

## Best Practices

### 1. Use FINAL Sparingly in Production
```ruby
# GOOD: For accurate counts/reports
def accurate_user_count
  User.final.count
end

# BETTER: For high-traffic queries, accept eventual consistency
def approximate_user_count
  User.count  # May include soon-to-be-merged duplicates
end
```

### 2. Consider Alternatives for Large Tables
```ruby
# For CollapsingMergeTree with Sign column
# INSTEAD OF:
Event.final.where(user_id: 123).sum(:amount)

# USE:
Event.where(user_id: 123).sum('amount * Sign')
```

### 3. Force Merge Offline for Consistent Reads
```ruby
# Run periodically (not per-request!)
client.command('OPTIMIZE TABLE users FINAL')

# Then queries without FINAL are consistent
User.where(id: 123).first
```

### 4. Use Settings-Based FINAL for Global Queries
```ruby
# When all queries in request need FINAL
Event.settings(final: 1).where(user_id: 123)
# Equivalent to: SELECT ... FROM events FINAL WHERE ...
```

---

## Implementation Details

### File Locations

| File | Purpose |
|------|---------|
| `lib/clickhouse_ruby/active_record/relation_extensions.rb` | `final` method |
| `lib/clickhouse_ruby/active_record/arel_visitor.rb` | SQL generation |
| `spec/unit/clickhouse_ruby/active_record/final_spec.rb` | Unit tests |
| `spec/integration/final_spec.rb` | Integration tests |

### RelationExtensions Addition

```ruby
# lib/clickhouse_ruby/active_record/relation_extensions.rb
module ClickhouseRuby
  module ActiveRecord
    module RelationExtensions
      # ... prewhere methods ...

      # FINAL support
      def final
        spawn.final!
      end

      def final!
        @use_final = true

        # Auto-add required settings when combining with prewhere
        if prewhere_values.any?
          @query_settings ||= {}
          @query_settings['optimize_move_to_prewhere'] = 1
          @query_settings['optimize_move_to_prewhere_if_final'] = 1
        end

        self
      end

      def final?
        @use_final || false
      end

      # Remove FINAL (for subqueries that shouldn't have it)
      def unscope_final
        spawn.tap { |r| r.instance_variable_set(:@use_final, false) }
      end
    end
  end
end
```

### Arel Visitor Modification

```ruby
# lib/clickhouse_ruby/active_record/arel_visitor.rb
class ClickhouseArelVisitor < Arel::Visitors::ToSql
  def visit_Arel_Nodes_SelectStatement(o, collector)
    # SELECT
    collector = visit_select_core(o.cores[0], collector)

    # FROM table_name
    collector << ' FROM '
    collector = visit(o.cores[0].source, collector)

    # FINAL (immediately after table name)
    if o.respond_to?(:final?) && o.final?
      collector << ' FINAL'
    end

    # SAMPLE, PREWHERE, WHERE, etc...
    collector = visit_remaining_clauses(o, collector)

    collector
  end
end
```

---

## Ralph Loop Checklist

- [ ] `final` method exists on relation
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/final_spec.rb --example "method exists"`

- [ ] `final` returns chainable relation
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/final_spec.rb --example "chainable"`

- [ ] `final` can be chained with `where`: `Model.final.where(id: 1)`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/final_spec.rb --example "chain with where"`

- [ ] `final` can be chained with `prewhere`: `Model.final.prewhere(active: true)`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/final_spec.rb --example "chain with prewhere"`

- [ ] Generated SQL includes FINAL after table name
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/final_spec.rb --example "SQL position"`

- [ ] `final?` predicate returns boolean
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/final_spec.rb --example "predicate"`

- [ ] Auto-adds settings when combined with prewhere
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/final_spec.rb --example "prewhere settings"`

- [ ] `unscope_final` removes FINAL modifier
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/final_spec.rb --example "unscope"`

- [ ] Integration test: FINAL with ReplacingMergeTree returns deduplicated rows
  **prove:** `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec spec/integration/final_spec.rb --example "ReplacingMergeTree"`

- [ ] All unit tests pass
  **prove:** `bundle exec rake spec_unit`

- [ ] No lint errors
  **prove:** `bundle exec rake rubocop`

---

## Test Scenarios

```ruby
# spec/unit/clickhouse_ruby/active_record/final_spec.rb
RSpec.describe 'FINAL modifier' do
  let(:model) do
    Class.new(ClickhouseRuby::ActiveRecord::Base) do
      self.table_name = 'users'
    end
  end

  describe '#final' do
    it 'generates FINAL in SQL' do
      sql = model.final.to_sql
      expect(sql).to include('FROM users FINAL')
    end

    it 'is chainable' do
      relation = model.final.where(id: 1)
      expect(relation).to be_a(ActiveRecord::Relation)
    end

    it 'places FINAL before WHERE' do
      sql = model.final.where(id: 1).to_sql

      final_pos = sql.index('FINAL')
      where_pos = sql.index('WHERE')

      expect(final_pos).to be < where_pos
    end

    it 'places FINAL before PREWHERE' do
      sql = model.final.prewhere(active: true).to_sql

      final_pos = sql.index('FINAL')
      prewhere_pos = sql.index('PREWHERE')

      expect(final_pos).to be < prewhere_pos
    end
  end

  describe '#final?' do
    it 'returns false by default' do
      expect(model.all.final?).to be false
    end

    it 'returns true after final called' do
      expect(model.final.final?).to be true
    end
  end

  describe '#unscope_final' do
    it 'removes FINAL modifier' do
      relation = model.final.unscope_final
      expect(relation.final?).to be false
      expect(relation.to_sql).not_to include('FINAL')
    end
  end

  describe 'with prewhere' do
    it 'auto-adds optimize settings' do
      relation = model.final.prewhere(active: true)
      settings = relation.query_settings

      expect(settings['optimize_move_to_prewhere']).to eq(1)
      expect(settings['optimize_move_to_prewhere_if_final']).to eq(1)
    end
  end
end

# spec/integration/final_spec.rb
RSpec.describe 'FINAL Integration', :integration do
  let(:client) { ClickhouseHelper.client }

  before do
    client.command(<<~SQL)
      CREATE TABLE IF NOT EXISTS final_test (
        id UInt64,
        name String,
        version UInt32
      ) ENGINE = ReplacingMergeTree(version)
      ORDER BY id
    SQL

    # Insert multiple versions of same row
    client.insert('final_test', [
      { id: 1, name: 'Alice', version: 1 },
      { id: 1, name: 'Alicia', version: 2 },
      { id: 2, name: 'Bob', version: 1 },
    ])
  end

  after do
    client.command('DROP TABLE IF EXISTS final_test')
  end

  it 'returns all rows without FINAL' do
    result = client.execute('SELECT * FROM final_test ORDER BY id, version')
    # May return 3 rows (duplicates not merged yet)
    expect(result.count).to be >= 2
  end

  it 'returns deduplicated rows with FINAL' do
    result = client.execute('SELECT * FROM final_test FINAL ORDER BY id')

    expect(result.count).to eq(2)  # Only 2 unique IDs

    alice = result.find { |r| r['id'] == 1 }
    expect(alice['name']).to eq('Alicia')  # Latest version
    expect(alice['version']).to eq(2)
  end
end
```

---

## SQL Examples

```ruby
# Basic FINAL
User.final
# SELECT * FROM users FINAL

# FINAL with WHERE
User.final.where(active: true)
# SELECT * FROM users FINAL WHERE active = 1

# FINAL with PREWHERE (auto-adds settings)
User.final.prewhere(created_at: Date.today..)
# SELECT * FROM users FINAL
# PREWHERE created_at >= '2024-01-31'
# SETTINGS optimize_move_to_prewhere = 1, optimize_move_to_prewhere_if_final = 1

# FINAL with aggregation
User.final.group(:status).count
# SELECT status, count() FROM users FINAL GROUP BY status

# Alternative via settings
User.settings(final: 1).where(id: 123)
# SELECT * FROM users WHERE id = 123 SETTINGS final = 1
```

---

## Performance Comparison

| Query Type | Without FINAL | With FINAL | Notes |
|------------|---------------|------------|-------|
| Simple SELECT | ~10ms | ~50ms | 5x slower |
| COUNT(*) | ~5ms | ~100ms | 20x slower (must read all data) |
| Aggregation | ~20ms | ~80ms | 4x slower |
| Large table (1B rows) | ~1s | ~30s | Significant impact |

**Recommendation:** Use FINAL only when accuracy is critical; otherwise accept eventual consistency or run `OPTIMIZE TABLE FINAL` offline.

---

## References

- [ClickHouse FINAL Documentation](https://clickhouse.com/docs/en/sql-reference/statements/select/from#final-modifier)
- [ReplacingMergeTree Engine](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [CollapsingMergeTree Engine](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/collapsingmergetree)
