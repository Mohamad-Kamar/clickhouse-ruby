# Feature: Query SETTINGS DSL

> **Status:** Implemented (v0.2.0)
> **Priority:** Core Feature (Released)
> **Dependencies:** RelationExtensions module (shared with PREWHERE, FINAL, SAMPLE)

---

## Guardrails

- **Don't change:** Existing client settings handling (already works at client level)
- **Must keep:** Chainable, appends SETTINGS at end of SQL, validates known settings
- **Definition of done:** All boxes checked + proof commands pass
- **Stop condition:** All checkboxes verified, integration test passes

---

## Research Summary

### What are Query SETTINGS?

ClickHouse allows per-query settings that override server/session defaults:

```sql
SELECT * FROM events
WHERE user_id = 123
SETTINGS max_execution_time = 60, max_rows_to_read = 1000000
```

### Common Settings

| Setting | Type | Description | Example |
|---------|------|-------------|---------|
| `max_execution_time` | UInt64 | Query timeout (seconds) | `60` |
| `max_rows_to_read` | UInt64 | Max rows to scan | `1000000` |
| `max_memory_usage` | UInt64 | Memory limit (bytes) | `10000000000` |
| `max_threads` | UInt64 | Parallel threads | `8` |
| `async_insert` | Bool | Enable async insert | `1` |
| `wait_for_async_insert` | Bool | Wait for async completion | `0` |
| `insert_deduplicate` | Bool | Deduplicate inserts | `1` |
| `final` | Bool | Apply FINAL to all queries | `1` |
| `optimize_read_in_order` | Bool | Optimize ORDER BY | `1` |
| `mutations_sync` | UInt64 | Wait for mutations | `2` |

### SQL Syntax

```sql
-- At end of query
SELECT ... FROM ... WHERE ... SETTINGS key1 = val1, key2 = val2

-- Multiple settings
SETTINGS max_execution_time = 60, max_threads = 4

-- Boolean settings (use 0/1)
SETTINGS async_insert = 1, wait_for_async_insert = 0
```

---

## Gotchas & Edge Cases

### 1. SETTINGS Position
```sql
-- SETTINGS must be at the END of the query
SELECT * FROM t WHERE x = 1 SETTINGS max_threads = 4  -- Correct
SELECT * FROM t SETTINGS max_threads = 4 WHERE x = 1  -- ERROR!
```

### 2. Unknown Settings Error
```sql
-- ClickHouse validates setting names
SELECT * FROM t SETTINGS invalid_setting = 1
-- ERROR: Unknown setting invalid_setting
```

**Ruby Implementation:** Let ClickHouse validate; optionally warn on unknown settings.

### 3. Boolean Values as Integers
```sql
-- Must use 0/1, not true/false
SETTINGS async_insert = 1    -- Correct
SETTINGS async_insert = true -- ERROR!
```

**Ruby Implementation:** Convert Ruby `true`/`false` to `1`/`0`.

### 4. String Values Need Quotes
```sql
-- String settings need single quotes
SETTINGS format = 'JSON'           -- Correct
SETTINGS format = JSON             -- ERROR!
```

### 5. Settings Don't Apply to Subqueries
```sql
-- SETTINGS only affects main query
SELECT * FROM (
  SELECT * FROM t  -- This subquery ignores outer SETTINGS
) SETTINGS max_threads = 4
```

### 6. Some Settings Require ALLOW_EXPERIMENTAL
```sql
-- New/experimental settings may require:
SET allow_experimental_analyzer = 1;
SELECT * FROM t SETTINGS use_analyzer = 1;
```

---

## Best Practices

### 1. Use Settings for Resource Limits
```ruby
# Prevent runaway queries
Event.settings(
  max_execution_time: 30,
  max_rows_to_read: 1_000_000
).where(user_id: 123)
```

### 2. Use Settings for Performance Tuning
```ruby
# Optimize specific queries
Event.settings(
  max_threads: 8,
  optimize_read_in_order: 1
).order(:created_at).limit(1000)
```

### 3. Use Settings for Async Insert
```ruby
# Fire-and-forget inserts
Event.settings(
  async_insert: 1,
  wait_for_async_insert: 0
).insert_all(records)
```

### 4. Use Settings for Mutations
```ruby
# Wait for DELETE/UPDATE to complete
Event.settings(mutations_sync: 2).where(deleted: true).delete_all
```

### 5. Chain Settings with Scopes
```ruby
# Define reusable settings scopes
class Event < ClickhouseRuby::ActiveRecord::Base
  scope :with_timeout, ->(seconds) { settings(max_execution_time: seconds) }
  scope :limited_scan, ->(rows) { settings(max_rows_to_read: rows) }
end

Event.with_timeout(30).limited_scan(1_000_000).where(active: true)
```

---

## Implementation Details

### File Locations

| File | Purpose |
|------|---------|
| `lib/clickhouse_ruby/active_record/relation_extensions.rb` | `settings` method |
| `lib/clickhouse_ruby/active_record/arel_visitor.rb` | SQL generation |
| `spec/unit/clickhouse_ruby/active_record/settings_spec.rb` | Unit tests |
| `spec/integration/settings_spec.rb` | Integration tests |

### RelationExtensions Addition

```ruby
# lib/clickhouse_ruby/active_record/relation_extensions.rb
module ClickhouseRuby
  module ActiveRecord
    module RelationExtensions
      # ... prewhere, final, sample methods ...

      # SETTINGS support
      def settings(opts = {})
        spawn.settings!(opts)
      end

      def settings!(opts)
        @query_settings ||= {}
        @query_settings.merge!(normalize_settings(opts))
        self
      end

      def query_settings
        @query_settings || {}
      end

      def settings_clause
        return nil if query_settings.empty?

        pairs = query_settings.map do |key, value|
          "#{key} = #{format_setting_value(value)}"
        end

        "SETTINGS #{pairs.join(', ')}"
      end

      private

      def normalize_settings(opts)
        opts.transform_keys(&:to_s).transform_values do |value|
          case value
          when true then 1
          when false then 0
          else value
          end
        end
      end

      def format_setting_value(value)
        case value
        when String
          "'#{value}'"
        when Integer, Float
          value.to_s
        else
          value.to_s
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
    # SELECT ... FROM ... WHERE ... ORDER BY ... LIMIT ...
    collector = visit_full_select(o, collector)

    # SETTINGS at the very end
    if o.query_settings&.any?
      collector << ' '
      collector << build_settings_clause(o.query_settings)
    end

    collector
  end

  private

  def build_settings_clause(settings)
    pairs = settings.map do |key, value|
      formatted = case value
                  when String then "'#{value}'"
                  when true then '1'
                  when false then '0'
                  else value.to_s
                  end
      "#{key} = #{formatted}"
    end

    "SETTINGS #{pairs.join(', ')}"
  end
end
```

### Known Settings Validation (Optional)

```ruby
# lib/clickhouse_ruby/active_record/settings_validator.rb
module ClickhouseRuby
  module ActiveRecord
    module SettingsValidator
      KNOWN_SETTINGS = %w[
        max_execution_time
        max_rows_to_read
        max_memory_usage
        max_threads
        async_insert
        wait_for_async_insert
        insert_deduplicate
        final
        optimize_read_in_order
        mutations_sync
        max_block_size
        max_insert_block_size
        max_bytes_to_read
        max_result_rows
        max_result_bytes
        read_overflow_mode
        result_overflow_mode
      ].freeze

      def self.validate(settings)
        unknown = settings.keys - KNOWN_SETTINGS
        if unknown.any?
          warn "Unknown ClickHouse settings: #{unknown.join(', ')}"
        end
      end
    end
  end
end
```

---

## Ralph Loop Checklist

- [ ] `settings(hash)` method exists on relation
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/settings_spec.rb --example "method exists"`

- [ ] `settings` returns chainable relation
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/settings_spec.rb --example "chainable"`

- [ ] Accepts common settings: `max_execution_time`, `async_insert`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/settings_spec.rb --example "common settings"`

- [ ] Generated SQL appends `SETTINGS key = val` at end
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/settings_spec.rb --example "SQL position"`

- [ ] Multiple settings separated by comma
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/settings_spec.rb --example "multiple settings"`

- [ ] Converts Ruby `true`/`false` to `1`/`0`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/settings_spec.rb --example "boolean conversion"`

- [ ] Quotes string values
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/settings_spec.rb --example "string quoting"`

- [ ] Multiple `settings` calls merge options
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/settings_spec.rb --example "merge"`

- [ ] Chains with other methods: `Model.settings(max_threads: 4).where(active: true)`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/active_record/settings_spec.rb --example "chain with where"`

- [ ] Integration test: settings affect query behavior
  **prove:** `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec spec/integration/settings_spec.rb`

- [ ] All unit tests pass
  **prove:** `bundle exec rake spec_unit`

- [ ] No lint errors
  **prove:** `bundle exec rake rubocop`

---

## Test Scenarios

```ruby
# spec/unit/clickhouse_ruby/active_record/settings_spec.rb
RSpec.describe 'SETTINGS DSL' do
  let(:model) do
    Class.new(ClickhouseRuby::ActiveRecord::Base) do
      self.table_name = 'events'
    end
  end

  describe '#settings' do
    it 'generates SETTINGS clause' do
      sql = model.settings(max_execution_time: 60).to_sql
      expect(sql).to include('SETTINGS max_execution_time = 60')
    end

    it 'handles multiple settings' do
      sql = model.settings(max_execution_time: 60, max_threads: 4).to_sql
      expect(sql).to include('max_execution_time = 60')
      expect(sql).to include('max_threads = 4')
    end

    it 'converts true to 1' do
      sql = model.settings(async_insert: true).to_sql
      expect(sql).to include('async_insert = 1')
    end

    it 'converts false to 0' do
      sql = model.settings(wait_for_async_insert: false).to_sql
      expect(sql).to include('wait_for_async_insert = 0')
    end

    it 'quotes string values' do
      sql = model.settings(format: 'JSON').to_sql
      expect(sql).to include("format = 'JSON'")
    end

    it 'merges multiple settings calls' do
      sql = model.settings(max_threads: 4).settings(max_execution_time: 60).to_sql
      expect(sql).to include('max_threads = 4')
      expect(sql).to include('max_execution_time = 60')
    end
  end

  describe 'SQL position' do
    it 'places SETTINGS at the end' do
      sql = model.where(active: true)
                 .order(:created_at)
                 .limit(100)
                 .settings(max_threads: 4)
                 .to_sql

      settings_pos = sql.index('SETTINGS')
      limit_pos = sql.index('LIMIT')

      expect(settings_pos).to be > limit_pos
    end
  end

  describe 'chainability' do
    it 'chains with where' do
      relation = model.settings(max_threads: 4).where(active: true)
      expect(relation.to_sql).to include('WHERE')
      expect(relation.to_sql).to include('SETTINGS')
    end

    it 'chains with prewhere' do
      relation = model.settings(final: 1).prewhere(date: Date.today)
      expect(relation.to_sql).to include('PREWHERE')
      expect(relation.to_sql).to include('SETTINGS')
    end
  end
end

# spec/integration/settings_spec.rb
RSpec.describe 'SETTINGS Integration', :integration do
  let(:client) { ClickhouseHelper.client }

  before do
    client.command(<<~SQL)
      CREATE TABLE IF NOT EXISTS settings_test (
        id UInt64,
        value UInt32
      ) ENGINE = MergeTree() ORDER BY id
    SQL

    rows = (1..100).map { |i| { id: i, value: i * 10 } }
    client.insert('settings_test', rows)
  end

  after do
    client.command('DROP TABLE IF EXISTS settings_test')
  end

  it 'applies max_rows_to_read setting' do
    # This should raise an error if limit exceeded
    expect {
      client.execute(<<~SQL)
        SELECT * FROM settings_test
        SETTINGS max_rows_to_read = 10
      SQL
    }.to raise_error(ClickhouseRuby::QueryError, /limit exceeded/)
  end

  it 'applies max_execution_time setting' do
    # Very short timeout should fail on any query
    expect {
      client.execute(<<~SQL)
        SELECT sleep(1) FROM settings_test
        SETTINGS max_execution_time = 0.001
      SQL
    }.to raise_error(ClickhouseRuby::QueryError, /timeout/)
  end

  it 'applies final setting' do
    result = client.execute(<<~SQL)
      SELECT count() AS cnt FROM settings_test
      SETTINGS final = 1
    SQL

    expect(result.first['cnt']).to eq(100)
  end
end
```

---

## SQL Examples

```ruby
# Simple timeout
Event.settings(max_execution_time: 30)
# SELECT * FROM events SETTINGS max_execution_time = 30

# Multiple settings
Event.settings(max_execution_time: 30, max_threads: 8)
# SELECT * FROM events SETTINGS max_execution_time = 30, max_threads = 8

# Boolean settings
Event.settings(async_insert: true, wait_for_async_insert: false)
# SELECT * FROM events SETTINGS async_insert = 1, wait_for_async_insert = 0

# Combined with full query
Event.prewhere(active: true)
     .where(category: 'sales')
     .order(:created_at)
     .limit(100)
     .settings(max_execution_time: 60, optimize_read_in_order: true)
# SELECT * FROM events
# PREWHERE active = 1
# WHERE category = 'sales'
# ORDER BY created_at
# LIMIT 100
# SETTINGS max_execution_time = 60, optimize_read_in_order = 1

# With final setting (alternative to .final method)
Event.settings(final: 1).where(user_id: 123)
# SELECT * FROM events WHERE user_id = 123 SETTINGS final = 1

# Mutations with sync
Event.settings(mutations_sync: 2).where(deleted: true).delete_all
# ALTER TABLE events DELETE WHERE deleted = 1 SETTINGS mutations_sync = 2
```

---

## References

- [ClickHouse SETTINGS Documentation](https://clickhouse.com/docs/en/sql-reference/statements/select#settings-in-select-query)
- [ClickHouse Settings Reference](https://clickhouse.com/docs/en/operations/settings/settings)
- [Query Complexity Settings](https://clickhouse.com/docs/en/operations/settings/query-complexity)
