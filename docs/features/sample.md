# Feature: SAMPLE Clause

> **Status:** Implemented (v0.2.0)
> **Priority:** Core Feature (Released)
> **Dependencies:** RelationExtensions module (shared with PREWHERE, FINAL, SETTINGS)

---

## Guardrails

- **Don't change:** Existing query generation, FROM clause handling
- **Must keep:** Support fractional, absolute, and offset variants; proper SQL positioning
- **Definition of done:** All boxes checked + proof commands pass
- **Stop condition:** All checkboxes verified, integration test passes

---

## Research Summary

### What is SAMPLE?

SAMPLE allows querying a subset of data for approximate results with faster execution:

```sql
-- 10% of data
SELECT count() FROM events SAMPLE 0.1

-- At least 10,000 rows
SELECT count() FROM events SAMPLE 10000

-- 10% starting at 50% offset (for reproducible subsets)
SELECT count() FROM events SAMPLE 0.1 OFFSET 0.5
```

### Requirements

**Table must be created with SAMPLE BY clause:**
```sql
CREATE TABLE events (
    id UInt64,
    ...
) ENGINE = MergeTree()
SAMPLE BY intHash32(id)  -- Required!
ORDER BY id;
```

### Syntax Variants

| Syntax | Meaning | Example |
|--------|---------|---------|
| `SAMPLE k` (0 < k < 1) | Fraction of data | `SAMPLE 0.1` = 10% |
| `SAMPLE n` (n >= 1) | At least n rows | `SAMPLE 10000` |
| `SAMPLE k OFFSET m` | Fraction with offset | `SAMPLE 0.1 OFFSET 0.5` |

### Result Adjustment

**Critical:** SAMPLE returns a subset - aggregates need manual adjustment!

```sql
-- WRONG: Returns count of 10% sample only
SELECT count() FROM events SAMPLE 0.1;  -- Returns ~1000 for 10000 rows

-- CORRECT: Multiply to estimate total
SELECT count() * 10 FROM events SAMPLE 0.1;  -- Returns ~10000

-- OR use _sample_factor virtual column
SELECT count() * _sample_factor FROM events SAMPLE 0.1;
```

**Exception:** Averages don't need adjustment:
```sql
SELECT avg(amount) FROM events SAMPLE 0.1;  -- Correct (average of sample ≈ average of population)
```

---

## Gotchas & Edge Cases

### 1. Table Must Have SAMPLE BY
```sql
-- Table without SAMPLE BY
CREATE TABLE t (id UInt64) ENGINE = MergeTree() ORDER BY id;

SELECT * FROM t SAMPLE 0.1;
-- ERROR: Cannot sample: table does not have SAMPLE BY expression
```

**Ruby Implementation:** Let ClickHouse raise the error; document requirement.

### 2. Deterministic Results
```sql
-- Same SAMPLE clause = same rows (deterministic)
SELECT * FROM events SAMPLE 0.1;  -- Returns rows A, B, C
SELECT * FROM events SAMPLE 0.1;  -- Returns same rows A, B, C

-- Different offset = different rows
SELECT * FROM events SAMPLE 0.1 OFFSET 0.0;  -- Rows A, B, C
SELECT * FROM events SAMPLE 0.1 OFFSET 0.1;  -- Rows D, E, F
```

### 3. Small Tables May Return Empty Results
```sql
-- Table with 100 rows
SELECT * FROM small_table SAMPLE 0.001;  -- May return 0 rows!

-- Use SAMPLE n for minimum guarantee
SELECT * FROM small_table SAMPLE 10;  -- At least 10 rows
```

### 4. SAMPLE with Aggregates
```sql
-- count(), sum() - MUST multiply by factor
SELECT count() * 10 FROM t SAMPLE 0.1;
SELECT sum(x) * 10 FROM t SAMPLE 0.1;

-- avg(), min(), max() - NO adjustment needed
SELECT avg(x) FROM t SAMPLE 0.1;

-- Complex aggregates - depends on function
SELECT quantile(0.95)(x) FROM t SAMPLE 0.1;  -- Usually OK
```

### 5. _sample_factor Virtual Column
```sql
-- Automatically contains 1/sample_ratio
SELECT count() * _sample_factor FROM t SAMPLE 0.1;
-- Equivalent to count() * 10

-- Also works with SAMPLE n
SELECT count() * _sample_factor FROM t SAMPLE 10000;
-- Factor calculated based on actual sample size
```

### 6. SAMPLE with FINAL
```sql
-- SAMPLE is applied AFTER FINAL
SELECT * FROM t FINAL SAMPLE 0.1;
-- First deduplicates, then samples from deduplicated result
```

### 7. Integer vs Float Detection
```sql
SAMPLE 10000   -- Integer: At least 10000 rows
SAMPLE 0.1     -- Float: 10% of data
SAMPLE 1       -- Integer 1: At least 1 row (NOT 100%!)
SAMPLE 1.0     -- Float 1.0: 100% of data
```

**Ruby Implementation:** Must differentiate `1` (Integer) from `1.0` (Float).

---

## Best Practices

### 1. Use SAMPLE for Exploratory Analysis
```ruby
# Quick data exploration on huge tables
Event.sample(0.01).limit(100)  # 1% sample, first 100 rows
```

### 2. Use SAMPLE for Approximate Counts
```ruby
# Fast approximate count
estimated = Event.sample(0.1).count * 10

# More accurate with _sample_factor
Event.select('count() * _sample_factor AS estimated_count').sample(0.1)
```

### 3. Use Absolute SAMPLE for Consistent Performance
```ruby
# Always read ~10K rows regardless of table size
Event.sample(10000).average(:amount)
```

### 4. Use OFFSET for Reproducible Subsets
```ruby
# Split data into 10 reproducible subsets for parallel processing
(0..9).map do |i|
  Event.sample(0.1, offset: i * 0.1)
end
```

### 5. Document Sample-Based Results
```ruby
# Make it clear results are approximate
def estimated_revenue
  sample_result = Event.sample(0.1).sum(:amount)
  {
    estimated_total: sample_result * 10,
    confidence: 'approximate (10% sample)',
    sample_size: Event.sample(0.1).count
  }
end
```

---

## Implementation Details

### File Locations

| File | Purpose |
|------|---------|
| `lib/clickhouse_ruby/active_record/relation_extensions.rb` | `sample` method |
| `lib/clickhouse_ruby/active_record/arel_visitor.rb` | SQL generation |
| `spec/unit/clickhouse_ruby/active_record/sample_spec.rb` | Unit tests |
| `spec/integration/sample_spec.rb` | Integration tests |

### RelationExtensions Addition

```ruby
# lib/clickhouse_ruby/active_record/relation_extensions.rb
module ClickhouseRuby
  module ActiveRecord
    module RelationExtensions
      # ... prewhere, final methods ...

      # SAMPLE support
      def sample(ratio_or_rows, offset: nil)
        spawn.sample!(ratio_or_rows, offset: offset)
      end

      def sample!(ratio_or_rows, offset: nil)
        @sample_value = ratio_or_rows
        @sample_offset = offset
        self
      end

      def sample_value
        @sample_value
      end

      def sample_offset
        @sample_offset
      end

      def sample_clause
        return nil unless @sample_value

        clause = "SAMPLE #{format_sample_value(@sample_value)}"
        clause += " OFFSET #{@sample_offset}" if @sample_offset
        clause
      end

      private

      def format_sample_value(value)
        case value
        when Float
          value.to_s
        when Integer
          value.to_s
        else
          value.to_f.to_s
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
    # SELECT ... FROM table
    collector = visit_select_and_from(o, collector)

    # FINAL
    collector << ' FINAL' if o.final?

    # SAMPLE (after FINAL, before PREWHERE)
    if o.sample_value
      collector << ' SAMPLE '
      collector << format_sample_value(o.sample_value)
      if o.sample_offset
        collector << ' OFFSET '
        collector << o.sample_offset.to_s
      end
    end

    # PREWHERE, WHERE, etc.
    collector = visit_remaining_clauses(o, collector)

    collector
  end

  private

  def format_sample_value(value)
    case value
    when Float
      value.to_s
    when Integer
      value.to_s
    else
      value.to_s
    end
  end
end
```

---

## Ralph Loop Checklist

- [ ] `sample(ratio)` method exists for fractional sampling (e.g., 0.1)
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/sample_spec.rb --example "fractional"`

- [ ] `sample(count)` method exists for absolute row count (e.g., 10000)
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/sample_spec.rb --example "absolute"`

- [ ] `sample(ratio, offset: n)` supports offset parameter
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/sample_spec.rb --example "offset"`

- [ ] Generated SQL: `SAMPLE 0.1` for fractional
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/sample_spec.rb --example "SQL fractional"`

- [ ] Generated SQL: `SAMPLE 10000` for absolute
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/sample_spec.rb --example "SQL absolute"`

- [ ] Generated SQL: `SAMPLE 0.1 OFFSET 0.5` with offset
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/sample_spec.rb --example "SQL offset"`

- [ ] Correctly differentiates integer 1 from float 1.0
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/sample_spec.rb --example "integer vs float"`

- [ ] SAMPLE positioned after FINAL, before PREWHERE
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/sample_spec.rb --example "SQL position"`

- [ ] Chainable with other methods: `Model.sample(0.1).where(active: true)`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/sample_spec.rb --example "chainable"`

- [ ] Integration test: SAMPLE query returns subset of data
  **prove:** `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec spec/integration/sample_spec.rb`

- [ ] All unit tests pass
  **prove:** `bundle exec rake spec_unit`

- [ ] No lint errors
  **prove:** `bundle exec rake rubocop`

---

## Test Scenarios

```ruby
# spec/unit/clickhouse_ruby/active_record/sample_spec.rb
RSpec.describe 'SAMPLE clause' do
  let(:model) do
    Class.new(ClickhouseRuby::ActiveRecord::Base) do
      self.table_name = 'events'
    end
  end

  describe '#sample' do
    context 'with fractional value' do
      it 'generates SAMPLE with float' do
        sql = model.sample(0.1).to_sql
        expect(sql).to include('SAMPLE 0.1')
      end
    end

    context 'with absolute value' do
      it 'generates SAMPLE with integer' do
        sql = model.sample(10000).to_sql
        expect(sql).to include('SAMPLE 10000')
      end
    end

    context 'with offset' do
      it 'generates SAMPLE with OFFSET' do
        sql = model.sample(0.1, offset: 0.5).to_sql
        expect(sql).to include('SAMPLE 0.1 OFFSET 0.5')
      end
    end

    context 'integer 1 vs float 1.0' do
      it 'treats integer 1 as "at least 1 row"' do
        sql = model.sample(1).to_sql
        expect(sql).to include('SAMPLE 1')
        expect(sql).not_to include('SAMPLE 1.0')
      end

      it 'treats float 1.0 as "100% of data"' do
        sql = model.sample(1.0).to_sql
        expect(sql).to include('SAMPLE 1.0')
      end
    end
  end

  describe 'SQL ordering' do
    it 'places SAMPLE after FINAL' do
      sql = model.final.sample(0.1).to_sql

      final_pos = sql.index('FINAL')
      sample_pos = sql.index('SAMPLE')

      expect(final_pos).to be < sample_pos
    end

    it 'places SAMPLE before PREWHERE' do
      sql = model.sample(0.1).prewhere(active: true).to_sql

      sample_pos = sql.index('SAMPLE')
      prewhere_pos = sql.index('PREWHERE')

      expect(sample_pos).to be < prewhere_pos
    end

    it 'places SAMPLE before WHERE' do
      sql = model.sample(0.1).where(status: 'done').to_sql

      sample_pos = sql.index('SAMPLE')
      where_pos = sql.index('WHERE')

      expect(sample_pos).to be < where_pos
    end
  end

  describe 'chainability' do
    it 'chains with where' do
      sql = model.sample(0.1).where(active: true).to_sql
      expect(sql).to include('SAMPLE 0.1')
      expect(sql).to include('WHERE')
    end

    it 'chains with limit' do
      sql = model.sample(0.1).limit(100).to_sql
      expect(sql).to include('SAMPLE 0.1')
      expect(sql).to include('LIMIT 100')
    end
  end
end

# spec/integration/sample_spec.rb
RSpec.describe 'SAMPLE Integration', :integration do
  let(:client) { ClickhouseHelper.client }

  before do
    client.command(<<~SQL)
      CREATE TABLE IF NOT EXISTS sample_test (
        id UInt64,
        value UInt32
      ) ENGINE = MergeTree()
      SAMPLE BY intHash32(id)
      ORDER BY id
    SQL

    # Insert 1000 rows
    rows = (1..1000).map { |i| { id: i, value: i * 10 } }
    client.insert('sample_test', rows)
  end

  after do
    client.command('DROP TABLE IF EXISTS sample_test')
  end

  it 'returns approximately 10% of rows with SAMPLE 0.1' do
    result = client.execute('SELECT count() AS cnt FROM sample_test SAMPLE 0.1')
    count = result.first['cnt']

    # Should be roughly 100 (10% of 1000), with some variance
    expect(count).to be_between(50, 150)
  end

  it 'returns at least n rows with SAMPLE n' do
    result = client.execute('SELECT count() AS cnt FROM sample_test SAMPLE 100')
    count = result.first['cnt']

    expect(count).to be >= 100
  end

  it 'returns deterministic results' do
    sql = 'SELECT id FROM sample_test SAMPLE 0.1 ORDER BY id'

    result1 = client.execute(sql).map { |r| r['id'] }
    result2 = client.execute(sql).map { |r| r['id'] }

    expect(result1).to eq(result2)
  end

  it 'returns different results with different offsets' do
    result1 = client.execute('SELECT id FROM sample_test SAMPLE 0.1 OFFSET 0.0 ORDER BY id')
    result2 = client.execute('SELECT id FROM sample_test SAMPLE 0.1 OFFSET 0.5 ORDER BY id')

    ids1 = result1.map { |r| r['id'] }
    ids2 = result2.map { |r| r['id'] }

    expect(ids1).not_to eq(ids2)
  end
end
```

---

## SQL Examples

```ruby
# Fractional sample (10% of data)
Event.sample(0.1)
# SELECT * FROM events SAMPLE 0.1

# Absolute sample (at least 10,000 rows)
Event.sample(10000)
# SELECT * FROM events SAMPLE 10000

# Sample with offset (reproducible subset)
Event.sample(0.1, offset: 0.5)
# SELECT * FROM events SAMPLE 0.1 OFFSET 0.5

# Combined with other clauses
Event.final.sample(0.1).prewhere(active: true).where(category: 'sales').limit(100)
# SELECT * FROM events
# FINAL
# SAMPLE 0.1
# PREWHERE active = 1
# WHERE category = 'sales'
# LIMIT 100

# Estimated count
Event.select('count() * 10 AS estimated_count').sample(0.1)
# SELECT count() * 10 AS estimated_count FROM events SAMPLE 0.1

# With _sample_factor
Event.select('count() * _sample_factor AS estimated_count').sample(0.1)
# SELECT count() * _sample_factor AS estimated_count FROM events SAMPLE 0.1
```

---

## References

- [ClickHouse SAMPLE Documentation](https://clickhouse.com/docs/en/sql-reference/statements/select/sample)
- [Sample By Expression](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#sample-by-expression)
