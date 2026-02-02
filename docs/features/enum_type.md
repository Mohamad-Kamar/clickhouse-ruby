# Feature: Enum Type Support

> **Status:** Not Started
> **Priority:** High (Batch 1)
> **Dependencies:** None

---

## Guardrails

- **Don't change:** Existing type system architecture, parser grammar
- **Must keep:** Type registry pattern, Base class interface, parser compatibility
- **Definition of done:** All boxes checked + proof commands pass
- **Stop condition:** All checkboxes verified, integration test passes

---

## Research Summary

### ClickHouse Enum Types

ClickHouse provides two enum types for storing a predefined set of string values as integers:

| Type | Storage | Value Range | Max Values |
|------|---------|-------------|------------|
| **Enum8** | 1 byte | [-128, 127] | 256 |
| **Enum16** | 2 bytes | [-32768, 32767] | 65,536 |

### Syntax Variations

```sql
-- Explicit value assignment
Enum('hello' = 1, 'world' = 2)
Enum8('active' = 1, 'inactive' = 2, 'pending' = 3)
Enum16('status_a' = 1000, 'status_b' = 2000)

-- Auto-increment from 1 (ClickHouse 21.8+)
Enum('hello', 'world')  -- hello=1, world=2
```

### Storage Behavior

- ClickHouse stores **only the numeric value** internally
- Displays string representation in query results
- Comparisons and sorting use **numeric ordering** (not alphabetical)
- NULL not allowed unless wrapped in `Nullable(Enum(...))`

---

## Gotchas & Edge Cases

### 1. Undefined Values Cause Exceptions
```sql
-- Table with Enum column
CREATE TABLE t (status Enum('active', 'inactive')) ENGINE = Memory;

-- This FAILS with exception
INSERT INTO t VALUES ('unknown');
-- Exception: Unknown element 'unknown' for type Enum
```

**Ruby Implementation:** Must validate against `@possible_values` in `cast()` and raise `TypeCastError`.

### 2. Numeric vs String Comparisons
```sql
-- Enum('b' = 1, 'a' = 2)
SELECT * FROM t WHERE status = 'a';  -- Works (string comparison)
SELECT * FROM t WHERE status = 2;    -- Works (numeric comparison)
SELECT * FROM t ORDER BY status;     -- Orders by numeric (b=1 before a=2)
```

**Ruby Implementation:** Support both string and integer inputs in `cast()`.

### 3. Type Coercion with CAST
```sql
-- Explicit conversions
SELECT CAST(status AS Int8) FROM t;   -- Returns numeric value
SELECT CAST(1 AS Enum('a' = 1));      -- Returns 'a'
```

### 4. Default Values
```sql
-- First enum value is NOT default
CREATE TABLE t (status Enum('a' = 2, 'b' = 1)) ENGINE = Memory;
INSERT INTO t (id) VALUES (1);  -- FAILS: no default for status
```

**Ruby Implementation:** Enum columns require explicit values on INSERT.

### 5. Parser Complexity
```sql
-- Values can contain special characters
Enum('it''s ok' = 1, 'value, with, commas' = 2)
-- Escaped quotes and commas inside values
```

**Ruby Implementation:** Parser must handle escaped quotes and commas within enum values.

---

## Best Practices

### 1. Use Enum for Low-Cardinality String Columns
- Better storage efficiency than String
- Faster comparisons (integer vs string)
- Schema-enforced data validation

### 2. Prefer Explicit Value Assignment
```sql
-- GOOD: Explicit values allow safe schema evolution
Enum('draft' = 1, 'published' = 2, 'archived' = 3)

-- RISKY: Auto-increment changes if order changes
Enum('draft', 'published', 'archived')
```

### 3. Consider LowCardinality(String) Alternative
- More flexible (no predefined values)
- Similar performance benefits
- Easier schema evolution

### 4. Validate in Application Layer
```ruby
# Catch invalid values before sending to ClickHouse
def status=(value)
  unless VALID_STATUSES.include?(value)
    raise ArgumentError, "Invalid status: #{value}"
  end
  super
end
```

---

## Implementation Details

### File Locations

| File | Purpose |
|------|---------|
| `lib/clickhouse_ruby/types/enum.rb` | Enum type class |
| `lib/clickhouse_ruby/types/registry.rb` | Register Enum8/Enum16 |
| `spec/unit/clickhouse_ruby/types/enum_spec.rb` | Unit tests |
| `spec/integration/types_spec.rb` | Integration tests |

### Type Class Structure

```ruby
# lib/clickhouse_ruby/types/enum.rb
module ClickhouseRuby
  module Types
    class Enum < Base
      attr_reader :possible_values, :value_to_int, :int_to_value

      def initialize(name, arg_types: nil)
        super(name)
        @possible_values, @value_to_int, @int_to_value = parse_enum_definition(name)
      end

      def cast(value)
        return nil if value.nil?

        case value
        when String
          validate_string_value!(value)
          value
        when Integer
          validate_int_value!(value)
          @int_to_value[value]
        else
          raise TypeCastError.new(
            "Cannot cast #{value.class} to Enum",
            from_type: value.class.name,
            to_type: to_s,
            value: value
          )
        end
      end

      def deserialize(value)
        # ClickHouse returns string representation
        value.to_s
      end

      def serialize(value)
        return 'NULL' if value.nil?
        # Quote for SQL
        "'#{value.to_s.gsub("'", "\\\\'")}'"
      end

      private

      def parse_enum_definition(type_string)
        # Extract values from: Enum8('a' = 1, 'b' = 2)
        # Returns: [['a', 'b'], {'a' => 1, 'b' => 2}, {1 => 'a', 2 => 'b'}]
      end

      def validate_string_value!(value)
        unless @possible_values.include?(value)
          raise TypeCastError.new(
            "Unknown enum value '#{value}'. Valid values: #{@possible_values.join(', ')}",
            from_type: 'String',
            to_type: to_s,
            value: value
          )
        end
      end

      def validate_int_value!(value)
        unless @int_to_value.key?(value)
          raise TypeCastError.new(
            "Unknown enum integer #{value}. Valid integers: #{@int_to_value.keys.join(', ')}",
            from_type: 'Integer',
            to_type: to_s,
            value: value
          )
        end
      end
    end
  end
end
```

### Parser Integration

The existing AST parser handles parameterized types. For Enum, the args contain string literals:

```ruby
# Parser output for Enum8('active' = 1, 'inactive' = 2)
{
  type: 'Enum8',
  args: [
    { type: 'literal', value: "'active' = 1" },
    { type: 'literal', value: "'inactive' = 2" }
  ]
}
```

### Registry Registration

```ruby
# In registry.rb register_defaults
register('Enum', Enum)
register('Enum8', Enum)
register('Enum16', Enum)
```

---

## Ralph Loop Checklist

- [ ] `Enum` type class exists at `lib/clickhouse_ruby/types/enum.rb`
  **prove:** `ruby -r./lib/clickhouse_ruby -e "ClickhouseRuby::Types::Enum"`

- [ ] Parser handles `Enum('a','b')` syntax
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "parses"`

- [ ] `cast()` converts String to valid enum value
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "cast string"`

- [ ] `cast()` converts Integer to enum value via mapping
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "cast integer"`

- [ ] `deserialize()` returns String from ClickHouse response
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "deserialize"`

- [ ] `serialize()` quotes value for SQL with escaped quotes
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "serialize"`

- [ ] Raises `TypeCastError` for invalid string values
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "invalid string"`

- [ ] Raises `TypeCastError` for invalid integer values
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/enum_spec.rb --example "invalid integer"`

- [ ] Registered in Types::Registry for Enum, Enum8, Enum16
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/registry_spec.rb --example "Enum"`

- [ ] Integration test: round-trip INSERT/SELECT with Enum column
  **prove:** `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec spec/integration/types_spec.rb --example "Enum"`

- [ ] All unit tests pass
  **prove:** `bundle exec rake spec_unit`

- [ ] No lint errors
  **prove:** `bundle exec rake rubocop`

---

## Test Scenarios

```ruby
# spec/unit/clickhouse_ruby/types/enum_spec.rb
RSpec.describe ClickhouseRuby::Types::Enum do
  subject(:type) { described_class.new("Enum8('active' = 1, 'inactive' = 2, 'pending' = 3)") }

  describe '#initialize' do
    it 'parses enum values' do
      expect(type.possible_values).to eq(['active', 'inactive', 'pending'])
    end

    it 'builds value-to-int mapping' do
      expect(type.value_to_int).to eq({ 'active' => 1, 'inactive' => 2, 'pending' => 3 })
    end
  end

  describe '#cast' do
    context 'with valid string' do
      it { expect(type.cast('active')).to eq('active') }
    end

    context 'with valid integer' do
      it { expect(type.cast(1)).to eq('active') }
      it { expect(type.cast(2)).to eq('inactive') }
    end

    context 'with invalid string' do
      it 'raises TypeCastError' do
        expect { type.cast('unknown') }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context 'with invalid integer' do
      it 'raises TypeCastError' do
        expect { type.cast(99) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context 'with nil' do
      it { expect(type.cast(nil)).to be_nil }
    end
  end

  describe '#serialize' do
    it { expect(type.serialize('active')).to eq("'active'") }
    it { expect(type.serialize(nil)).to eq('NULL') }

    it 'escapes quotes' do
      # For enum like Enum("it's" = 1)
      expect(type.serialize("it's")).to eq("'it\\'s'")
    end
  end
end
```

---

## References

- [ClickHouse Enum Documentation](https://clickhouse.com/docs/en/sql-reference/data-types/enum)
- [clickhouse-go Enum Implementation](https://github.com/ClickHouse/clickhouse-go/blob/main/lib/column/enum.go)
