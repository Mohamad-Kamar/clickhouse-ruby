# Feature: PREWHERE Support

> **Status:** Not Started
> **Priority:** High (Batch 3) - Most requested feature
> **Dependencies:** RelationExtensions module (shared with FINAL, SAMPLE, SETTINGS)

---

## Guardrails

- **Don't change:** Existing WHERE clause handling, Arel visitor base behavior
- **Must keep:** Chainable with where(), proper SQL ordering (PREWHERE before WHERE), ActiveRecord patterns
- **Definition of done:** All boxes checked + proof commands pass
- **Stop condition:** All checkboxes verified, integration test passes

---

## Research Summary

### What is PREWHERE?

PREWHERE is a ClickHouse-specific optimization that filters data at an earlier stage than WHERE:

```
Query Pipeline:
1. Read data from disk (only PREWHERE columns)
2. Apply PREWHERE filter (eliminate blocks)
3. Read remaining columns (only for passing rows)
4. Apply WHERE filter
5. Return results
```

### SQL Syntax

```sql
SELECT * FROM events
PREWHERE date > '2024-01-01'     -- Applied first, on fewer columns
WHERE status = 'active'           -- Applied after PREWHERE
```

**Clause Ordering:**
```sql
SELECT ... FROM table
[FINAL]
[SAMPLE n]
[PREWHERE expr]
[WHERE expr]
[GROUP BY ...]
[ORDER BY ...]
[LIMIT n]
```

### Performance Impact

| Scenario | Without PREWHERE | With PREWHERE | Improvement |
|----------|------------------|---------------|-------------|
| Filter 90% of data | Read all columns | Read filter column only | 5-10x less I/O |
| High selectivity | Full table scan | Block skipping | 2-5x faster |

### Automatic Optimization

ClickHouse automatically moves suitable WHERE conditions to PREWHERE when:
- `optimize_move_to_prewhere = 1` (default)
- Condition uses columns not in primary key
- Condition has high selectivity

**When to use explicit PREWHERE:**
- Force specific optimization
- Complex conditions where auto-optimization fails
- Testing/benchmarking

---

## Gotchas & Edge Cases

### 1. Only Works on MergeTree Family
```sql
-- Works
SELECT * FROM mergetree_table PREWHERE x > 1

-- ERROR: PREWHERE is not supported
SELECT * FROM memory_table PREWHERE x > 1
SELECT * FROM log_table PREWHERE x > 1
```

**Ruby Implementation:** Document this limitation; let ClickHouse raise the error.

### 2. Cannot Use with Multiple JOINs
```sql
-- ERROR: PREWHERE not available with multiple JOINs
SELECT * FROM t1
PREWHERE x > 1
JOIN t2 ON t1.id = t2.t1_id
JOIN t3 ON t2.id = t3.t2_id
```

**Workaround:** Move PREWHERE to subquery:
```sql
SELECT * FROM (SELECT * FROM t1 PREWHERE x > 1) AS t1
JOIN t2 ON t1.id = t2.t1_id
JOIN t3 ON t2.id = t3.t2_id
```

### 3. PREWHERE with FINAL Requires Settings
```sql
-- May not work without settings
SELECT * FROM table FINAL PREWHERE x > 1

-- Enable both settings
SET optimize_move_to_prewhere = 1;
SET optimize_move_to_prewhere_if_final = 1;
SELECT * FROM table FINAL PREWHERE x > 1
```

**Ruby Implementation:** Automatically add settings when combining `prewhere` with `final`.

### 4. Column Expression Limitations
```sql
-- PREWHERE works with:
PREWHERE column > value
PREWHERE column IN (1, 2, 3)
PREWHERE column BETWEEN a AND b

-- PREWHERE may not optimize:
PREWHERE function(column) > value  -- Function on column
PREWHERE col1 + col2 > value       -- Expression
```

### 5. Interaction with Projection
```sql
-- PREWHERE is applied AFTER projection selection
-- If projection doesn't include PREWHERE column, full table scanned
```

---

## Best Practices

### 1. Use PREWHERE for Date/Time Filters
```ruby
# Date columns are often partition keys - excellent for PREWHERE
Event.prewhere('event_date >= ?', 1.month.ago)
     .where(user_id: 123)
```

### 2. Use PREWHERE for Low-Cardinality Filters
```ruby
# Boolean/enum columns filter out large blocks
Event.prewhere(active: true)
     .where(category: 'sales')
```

### 3. Combine with WHERE for Complex Queries
```ruby
# PREWHERE: Coarse filter (eliminates blocks)
# WHERE: Fine filter (eliminates rows within blocks)
Event.prewhere('date >= ?', start_date)
     .where('amount > ? AND status = ?', 100, 'completed')
```

### 4. Let Auto-Optimization Work
```ruby
# Often, just use where() and let ClickHouse optimize
Event.where(date: date_range, status: 'active')
# ClickHouse will automatically move suitable conditions to PREWHERE
```

---

## Implementation Details

### File Locations

| File | Purpose |
|------|---------|
| `lib/clickhouse_ruby/active_record/relation_extensions.rb` | PREWHERE method (new) |
| `lib/clickhouse_ruby/active_record/arel_visitor.rb` | SQL generation |
| `lib/clickhouse_ruby/active_record/connection_adapter.rb` | Extend relation |
| `spec/unit/clickhouse_ruby/active_record/prewhere_spec.rb` | Unit tests |
| `spec/integration/prewhere_spec.rb` | Integration tests |

### RelationExtensions Module

```ruby
# lib/clickhouse_ruby/active_record/relation_extensions.rb
module ClickhouseRuby
  module ActiveRecord
    module RelationExtensions
      extend ActiveSupport::Concern

      # PREWHERE support
      def prewhere(opts = :chain, *rest)
        if opts == :chain
          PrewhereChain.new(spawn)
        elsif opts.blank?
          self
        else
          spawn.prewhere!(opts, *rest)
        end
      end

      def prewhere!(opts, *rest)
        @prewhere_values ||= []

        case opts
        when String
          @prewhere_values << Arel.sql(sanitize_sql(opts, rest))
        when Hash
          opts.each do |key, value|
            @prewhere_values << build_prewhere_condition(key, value)
          end
        when Arel::Nodes::Node
          @prewhere_values << opts
        end

        self
      end

      def prewhere_values
        @prewhere_values || []
      end

      private

      def build_prewhere_condition(column, value)
        arel_table = self.arel_table

        case value
        when nil
          arel_table[column].eq(nil)
        when Array
          arel_table[column].in(value)
        when Range
          arel_table[column].between(value)
        else
          arel_table[column].eq(value)
        end
      end

      class PrewhereChain
        def initialize(relation)
          @relation = relation
        end

        def not(opts, *rest)
          @relation.prewhere!(Arel::Nodes::Not.new(opts))
        end
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
    collector = visit_Arel_Nodes_SelectCore(o.cores[0], collector)

    # FROM
    collector = visit(o.cores[0].source, collector)

    # FINAL (if set)
    collector << ' FINAL' if o.final

    # SAMPLE (if set)
    if o.sample
      collector << ' SAMPLE '
      collector = visit(o.sample, collector)
    end

    # PREWHERE (new)
    if o.prewhere_values&.any?
      collector << ' PREWHERE '
      collector = visit_prewhere_conditions(o.prewhere_values, collector)
    end

    # WHERE
    if o.wheres.any?
      collector << ' WHERE '
      collector = visit_where_conditions(o.wheres, collector)
    end

    # GROUP BY, HAVING, ORDER BY, LIMIT, OFFSET
    collector = visit_orders_and_limits(o, collector)

    collector
  end

  private

  def visit_prewhere_conditions(conditions, collector)
    conditions.each_with_index do |condition, i|
      collector << ' AND ' if i > 0
      collector = visit(condition, collector)
    end
    collector
  end
end
```

### Adapter Integration

```ruby
# lib/clickhouse_ruby/active_record/connection_adapter.rb
class ConnectionAdapter < AbstractAdapter
  def initialize(...)
    # ... existing ...

    # Extend ActiveRecord::Relation with our methods
    ::ActiveRecord::Relation.include(RelationExtensions)
  end
end
```

---

## Ralph Loop Checklist

- [ ] `RelationExtensions` module exists at `lib/clickhouse_ruby/active_record/relation_extensions.rb`
  **prove:** `ruby -r./lib/clickhouse_ruby/active_record -e "ClickhouseRuby::ActiveRecord::RelationExtensions"`

- [ ] `prewhere(conditions)` method returns chainable relation
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/prewhere_spec.rb --example "returns relation"`

- [ ] `prewhere` accepts hash conditions: `prewhere(status: 'active')`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/prewhere_spec.rb --example "hash conditions"`

- [ ] `prewhere` accepts string conditions: `prewhere('price > 100')`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/prewhere_spec.rb --example "string conditions"`

- [ ] `prewhere` accepts string with placeholders: `prewhere('date > ?', date)`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/prewhere_spec.rb --example "placeholders"`

- [ ] Generated SQL has PREWHERE before WHERE
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/prewhere_spec.rb --example "SQL ordering"`

- [ ] Multiple prewhere calls are ANDed together
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/prewhere_spec.rb --example "multiple prewhere"`

- [ ] `prewhere` chains with `where`: `Model.prewhere(a: 1).where(b: 2)`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/prewhere_spec.rb --example "chain with where"`

- [ ] `prewhere.not` works: `Model.prewhere.not(deleted: true)`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/prewhere_spec.rb --example "prewhere not"`

- [ ] Integration test: PREWHERE query executes successfully on MergeTree
  **prove:** `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec spec/integration/prewhere_spec.rb`

- [ ] All unit tests pass
  **prove:** `bundle exec rake spec_unit`

- [ ] No lint errors
  **prove:** `bundle exec rake rubocop`

---

## Test Scenarios

```ruby
# spec/unit/clickhouse_ruby/active_record/prewhere_spec.rb
RSpec.describe 'PREWHERE support' do
  let(:model) do
    Class.new(ClickhouseRuby::ActiveRecord::Base) do
      self.table_name = 'events'
    end
  end

  describe '#prewhere' do
    it 'generates PREWHERE clause with hash' do
      sql = model.prewhere(active: true).to_sql
      expect(sql).to include('PREWHERE')
      expect(sql).to include("active = 1")
    end

    it 'generates PREWHERE clause with string' do
      sql = model.prewhere('date > ?', '2024-01-01').to_sql
      expect(sql).to include("PREWHERE date > '2024-01-01'")
    end

    it 'places PREWHERE before WHERE' do
      sql = model.prewhere(active: true).where(status: 'done').to_sql

      prewhere_pos = sql.index('PREWHERE')
      where_pos = sql.index('WHERE')

      expect(prewhere_pos).to be < where_pos
    end

    it 'ANDs multiple prewhere conditions' do
      sql = model.prewhere(active: true).prewhere(deleted: false).to_sql
      expect(sql).to include('PREWHERE')
      expect(sql).to include('AND')
    end

    it 'supports IN conditions' do
      sql = model.prewhere(status: ['a', 'b', 'c']).to_sql
      expect(sql).to include("status IN ('a', 'b', 'c')")
    end

    it 'supports range conditions' do
      sql = model.prewhere(id: 1..100).to_sql
      expect(sql).to include('BETWEEN 1 AND 100')
    end
  end

  describe '#prewhere.not' do
    it 'negates the condition' do
      sql = model.prewhere.not(deleted: true).to_sql
      expect(sql).to include('NOT')
    end
  end
end

# spec/integration/prewhere_spec.rb
RSpec.describe 'PREWHERE Integration', :integration do
  let(:client) { ClickhouseHelper.client }

  before do
    client.command(<<~SQL)
      CREATE TABLE IF NOT EXISTS prewhere_test (
        date Date,
        status String,
        amount UInt32
      ) ENGINE = MergeTree()
      ORDER BY date
    SQL

    client.insert('prewhere_test', [
      { date: '2024-01-01', status: 'active', amount: 100 },
      { date: '2024-01-02', status: 'inactive', amount: 200 },
      { date: '2024-01-03', status: 'active', amount: 300 },
    ])
  end

  after do
    client.command('DROP TABLE IF EXISTS prewhere_test')
  end

  it 'executes PREWHERE query successfully' do
    result = client.execute(<<~SQL)
      SELECT * FROM prewhere_test
      PREWHERE date >= '2024-01-02'
      WHERE status = 'active'
    SQL

    expect(result.count).to eq(1)
    expect(result.first['amount']).to eq(300)
  end
end
```

---

## SQL Examples

```ruby
# Simple PREWHERE
Event.prewhere(active: true)
# SELECT * FROM events PREWHERE active = 1

# PREWHERE with WHERE
Event.prewhere('date >= ?', 1.week.ago).where(user_id: 123)
# SELECT * FROM events PREWHERE date >= '2024-01-24' WHERE user_id = 123

# Multiple PREWHERE conditions
Event.prewhere(active: true).prewhere('amount > 100')
# SELECT * FROM events PREWHERE active = 1 AND amount > 100

# PREWHERE with FINAL
Event.prewhere(date: Date.today).final
# SELECT * FROM events FINAL PREWHERE date = '2024-01-31'

# Chained with all query methods
Event.prewhere(active: true)
     .where(category: 'sales')
     .order(created_at: :desc)
     .limit(100)
# SELECT * FROM events
# PREWHERE active = 1
# WHERE category = 'sales'
# ORDER BY created_at DESC
# LIMIT 100
```

---

## References

- [ClickHouse PREWHERE Documentation](https://clickhouse.com/docs/en/sql-reference/statements/select/prewhere)
- [ClickHouse Query Optimization](https://clickhouse.com/docs/en/sql-reference/statements/select/prewhere#controlling-prewhere-manually)
- [ActiveRecord Query Interface](https://guides.rubyonrails.org/active_record_querying.html)
