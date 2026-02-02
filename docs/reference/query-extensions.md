# Query Extensions Reference

ClickHouse-specific query extensions available in ActiveRecord.

## Overview

| Extension | Purpose | SQL Syntax |
|-----------|---------|------------|
| [PREWHERE](#prewhere) | Query optimization | `PREWHERE expr WHERE expr` |
| [FINAL](#final) | Deduplication | `FROM table FINAL` |
| [SAMPLE](#sample) | Approximate queries | `SAMPLE 0.1` |
| [SETTINGS](#settings) | Per-query config | `SETTINGS key = value` |

## SQL Clause Ordering

```sql
SELECT ...
FROM table FINAL           -- 1. FINAL (deduplication)
SAMPLE 0.1                  -- 2. SAMPLE (sampling)
PREWHERE date > '2024-01-01' -- 3. PREWHERE (early filter)
WHERE status = 'active'     -- 4. WHERE (filter)
GROUP BY ...
ORDER BY ...
LIMIT n
SETTINGS max_threads = 4    -- Last: SETTINGS
```

---

## PREWHERE

Filters data at an earlier stage than WHERE, reading fewer columns.

### Ruby Usage

```ruby
# Basic PREWHERE
Event.prewhere(date: Date.today).where(status: 'active')

# String conditions
Event.prewhere('date > ?', 1.day.ago)

# Negation
Event.prewhere.not(deleted: true)
```

### Generated SQL

```sql
SELECT * FROM events
PREWHERE date = '2024-01-15'
WHERE status = 'active'
```

### When to Use

- High-selectivity filters (eliminate >50% of data)
- Date/time range filters
- Columns not in primary key

### Gotchas

- **MergeTree only** - Does not work with Memory, Log tables
- **No multiple JOINs** - Move to subquery if needed
- **Auto-optimization** - ClickHouse moves WHERE to PREWHERE automatically when beneficial

---

## FINAL

Forces data merge at query time for *MergeTree tables.

### Ruby Usage

```ruby
# Basic FINAL
User.final.where(id: 123)

# Combined with other methods
User.final.prewhere(created_at: 1.week.ago..).where(active: true)
```

### Generated SQL

```sql
SELECT * FROM users FINAL WHERE id = 123
```

### When to Use

- ReplacingMergeTree (get latest version)
- CollapsingMergeTree (get collapsed rows)
- When data accuracy is critical

### Table Engines

| Engine | FINAL Behavior |
|--------|----------------|
| ReplacingMergeTree | Returns latest version |
| CollapsingMergeTree | Returns collapsed rows |
| SummingMergeTree | Returns summed values |

### Gotchas

- **Performance cost** - 2-10x slower (merges during query)
- **PREWHERE combination** - Auto-adds optimization settings
- **Alternative** - Use `OPTIMIZE TABLE ... FINAL` for offline merge

---

## SAMPLE

Queries a subset of data for approximate results.

### Ruby Usage

```ruby
# Fractional (10% of data)
Event.sample(0.1).count

# Absolute (at least 10,000 rows)
Event.sample(10000).count

# With offset (reproducible subset)
Event.sample(0.1, offset: 0.5).count
```

### Generated SQL

```sql
SELECT count() FROM events SAMPLE 0.1
SELECT count() FROM events SAMPLE 10000
SELECT count() FROM events SAMPLE 0.1 OFFSET 0.5
```

### Syntax Variants

| Ruby | SQL | Meaning |
|------|-----|---------|
| `sample(0.1)` | `SAMPLE 0.1` | 10% of data |
| `sample(10000)` | `SAMPLE 10000` | At least 10K rows |
| `sample(0.1, offset: 0.5)` | `SAMPLE 0.1 OFFSET 0.5` | 10% starting at 50% |

### Result Adjustment

```ruby
# WRONG: Returns count of sample only
Event.sample(0.1).count  # => ~1000 for 10K rows

# CORRECT: Multiply to estimate total
Event.sample(0.1).count * 10  # => ~10000

# Averages don't need adjustment
Event.sample(0.1).average(:amount)  # Correct as-is
```

### Gotchas

- **Requires SAMPLE BY** - Table must be created with `SAMPLE BY` clause
- **Integer vs Float** - `sample(1)` = "at least 1 row", `sample(1.0)` = "100%"
- **Deterministic** - Same SAMPLE returns same rows

---

## SETTINGS

Applies per-query ClickHouse settings.

### Ruby Usage

```ruby
# Single setting
Event.settings(max_execution_time: 60).all

# Multiple settings
Event.settings(max_threads: 4, async_insert: true).all

# Boolean normalization (true → 1, false → 0)
Event.settings(final: true).all
```

### Generated SQL

```sql
SELECT * FROM events SETTINGS max_execution_time = 60
SELECT * FROM events SETTINGS max_threads = 4, async_insert = 1
SELECT * FROM events SETTINGS final = 1
```

### Common Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `max_execution_time` | 0 | Query timeout (seconds, 0 = no limit) |
| `max_rows_to_read` | 0 | Max rows to read (0 = no limit) |
| `max_threads` | auto | Parallel query threads |
| `async_insert` | 0 | Enable async inserts |
| `final` | 0 | Force FINAL modifier |

### Gotchas

- **Position** - SETTINGS must be at end of query
- **Unknown settings** - ClickHouse raises error for invalid settings
- **Boolean values** - Ruby booleans converted to 0/1

---

## Combining Extensions

```ruby
# All extensions together
User.final
    .prewhere(created_at: 1.week.ago..)
    .where(status: 'active')
    .sample(0.1)
    .settings(max_threads: 4)
    .order(id: :desc)
    .limit(100)
```

Generated SQL:

```sql
SELECT * FROM users FINAL
SAMPLE 0.1
PREWHERE created_at >= '2024-01-08'
WHERE status = 'active'
ORDER BY id DESC
LIMIT 100
SETTINGS max_threads = 4
```

## See Also

- **[ActiveRecord Guide](../guides/activerecord.md)** - Complete ActiveRecord usage
- **[Querying Guide](../guides/querying.md)** - Query patterns
