# Feature: Decimal Type Support

> **Status:** Not Started
> **Priority:** High (Batch 1)
> **Dependencies:** None

---

## Guardrails

- **Don't change:** Existing numeric type implementations (Integer, Float)
- **Must keep:** Use Ruby BigDecimal for precision, validate P/S constraints
- **Definition of done:** All boxes checked + proof commands pass
- **Stop condition:** All checkboxes verified, integration test passes

---

## Research Summary

### ClickHouse Decimal Types

ClickHouse Decimal types store fixed-point numbers with exact precision:

| Syntax | Precision (P) | Scale (S) | Internal Type | Storage |
|--------|---------------|-----------|---------------|---------|
| `Decimal(P, S)` | 1-9 | 0-P | Decimal32 | 4 bytes |
| `Decimal(P, S)` | 10-18 | 0-P | Decimal64 | 8 bytes |
| `Decimal(P, S)` | 19-38 | 0-P | Decimal128 | 16 bytes |
| `Decimal(P, S)` | 39-76 | 0-P | Decimal256 | 32 bytes |

### Parameters

- **Precision (P):** Total number of significant digits (1-76)
- **Scale (S):** Number of digits after decimal point (0 to P)
- **Default:** `Decimal(10, 0)` when parameters omitted

### Shorthand Aliases

```sql
Decimal32(S)   -- Equivalent to Decimal(9, S)
Decimal64(S)   -- Equivalent to Decimal(18, S)
Decimal128(S)  -- Equivalent to Decimal(38, S)
Decimal256(S)  -- Equivalent to Decimal(76, S)
```

---

## Gotchas & Edge Cases

### 1. Precision Overflow
```sql
-- Decimal(5, 2) allows up to 999.99
INSERT INTO t VALUES (1000.00);  -- OVERFLOW ERROR!
INSERT INTO t VALUES (99.999);   -- TRUNCATED to 99.99 (scale overflow)
```

**Ruby Implementation:** Validate that `value.to_s.gsub(/\D/, '').length <= precision` before serialization.

### 2. Division Truncation (Not Rounding!)
```sql
SELECT CAST(1 AS Decimal(10,4)) / CAST(3 AS Decimal(10,4));
-- Returns 0.3333 (truncated, NOT 0.3334 rounded)
```

**Ruby Implementation:** Document this behavior - results may differ from Ruby's BigDecimal division.

### 3. Arithmetic Result Scale
```sql
-- Addition/Subtraction: max(scale1, scale2)
-- Multiplication: scale1 + scale2
-- Division: scale1 (truncated)

Decimal(10,2) + Decimal(10,4) → Decimal(10,4)
Decimal(10,2) * Decimal(10,4) → Decimal(10,6)
Decimal(10,4) / Decimal(10,2) → Decimal(10,4)
```

### 4. Decimal128/256 Overflow Behavior
```sql
-- Decimal32/64: Throws exception on overflow
-- Decimal128/256: SILENT overflow (wraps around!)
```

**Ruby Implementation:** Add warning in documentation. Consider client-side overflow check for Decimal128/256.

### 5. String Conversion Precision Loss
```sql
-- Converting from String preserves all digits
SELECT CAST('123.456789012345678901234567890' AS Decimal(38, 30));
-- Works - all digits preserved

-- But Float conversion loses precision
SELECT CAST(123.456789012345678901234567890 AS Decimal(38, 30));
-- Loses precision - Float only has ~15 significant digits
```

**Ruby Implementation:** Use String intermediate for BigDecimal serialization, never Float.

### 6. Zero Scale Behavior
```sql
Decimal(10, 0) -- Integer-like storage
INSERT INTO t VALUES (123.45);  -- Stored as 123 (truncated)
```

---

## Best Practices

### 1. Use BigDecimal in Ruby
```ruby
# GOOD: Preserves precision
BigDecimal('123.456789012345678901234567890')

# BAD: Float loses precision
BigDecimal(123.456789012345678901234567890)  # Precision lost!
```

### 2. Match Precision to Use Case
```sql
-- Currency: Decimal(18, 2) or Decimal(18, 4)
-- Scientific: Decimal(38, 10)
-- Financial calculations: Decimal(38, 18)
```

### 3. Validate Before INSERT
```ruby
def validate_decimal(value, precision, scale)
  bd = BigDecimal(value.to_s)
  integer_digits = bd.fix.to_s('F').gsub(/[^0-9]/, '').length
  fractional_digits = bd.frac.to_s('F').split('.')[1]&.length || 0

  raise PrecisionError if integer_digits > (precision - scale)
  raise ScaleError if fractional_digits > scale
end
```

### 4. Prefer Decimal Over Float
```sql
-- GOOD: Exact values for financial data
amount Decimal(18, 4)

-- BAD: Floating point errors
amount Float64  -- 0.1 + 0.2 != 0.3
```

---

## Implementation Details

### File Locations

| File | Purpose |
|------|---------|
| `lib/clickhouse_ruby/types/decimal.rb` | Decimal type class |
| `lib/clickhouse_ruby/types/registry.rb` | Register Decimal variants |
| `spec/unit/clickhouse_ruby/types/decimal_spec.rb` | Unit tests |
| `spec/integration/types_spec.rb` | Integration tests |

### Type Class Structure

```ruby
# lib/clickhouse_ruby/types/decimal.rb
module ClickhouseRuby
  module Types
    class Decimal < Base
      attr_reader :precision, :scale

      # Precision limits per internal type
      PRECISION_LIMITS = {
        32 => 9,
        64 => 18,
        128 => 38,
        256 => 76
      }.freeze

      def initialize(name, precision: nil, scale: nil)
        super(name)
        @precision, @scale = parse_decimal_params(name, precision, scale)
        validate_params!
      end

      def cast(value)
        return nil if value.nil?

        bd = case value
             when ::BigDecimal
               value
             when ::Integer
               ::BigDecimal(value)
             when ::Float
               # Warn about precision loss
               ::BigDecimal(value, precision)
             when ::String
               ::BigDecimal(value)
             else
               raise TypeCastError.new(
                 "Cannot cast #{value.class} to Decimal",
                 from_type: value.class.name,
                 to_type: to_s,
                 value: value
               )
             end

        validate_value!(bd)
        bd
      end

      def deserialize(value)
        return nil if value.nil?
        ::BigDecimal(value.to_s)
      end

      def serialize(value)
        return 'NULL' if value.nil?

        bd = cast(value)
        # Use string format to preserve precision
        bd.to_s('F')
      end

      def internal_type
        case precision
        when 1..9   then :Decimal32
        when 10..18 then :Decimal64
        when 19..38 then :Decimal128
        when 39..76 then :Decimal256
        end
      end

      private

      def parse_decimal_params(name, precision, scale)
        # Parse from type string: Decimal(18, 4) or Decimal64(4)
        if name =~ /Decimal(\d+)?\((\d+)(?:,\s*(\d+))?\)/
          variant = $1&.to_i
          p = $2.to_i
          s = $3&.to_i || 0

          if variant
            # Decimal32(4) → precision from variant, scale from arg
            max_p = PRECISION_LIMITS[variant]
            [max_p, s]
          else
            [p, s]
          end
        else
          [precision || 10, scale || 0]
        end
      end

      def validate_params!
        unless (1..76).include?(@precision)
          raise ConfigurationError, "Decimal precision must be 1-76, got #{@precision}"
        end

        unless (0..@precision).include?(@scale)
          raise ConfigurationError, "Decimal scale must be 0-#{@precision}, got #{@scale}"
        end
      end

      def validate_value!(bd)
        # Check integer part doesn't exceed allowed digits
        max_integer_digits = @precision - @scale
        integer_part = bd.fix.abs

        if integer_part.to_s('F').gsub(/[^0-9]/, '').length > max_integer_digits
          raise TypeCastError.new(
            "Value #{bd} exceeds maximum integer digits (#{max_integer_digits}) for #{to_s}",
            from_type: 'BigDecimal',
            to_type: to_s,
            value: bd
          )
        end
      end
    end
  end
end
```

### Registry Registration

```ruby
# In registry.rb register_defaults
register('Decimal', Decimal)
register('Decimal32', Decimal)
register('Decimal64', Decimal)
register('Decimal128', Decimal)
register('Decimal256', Decimal)
```

---

## Ralph Loop Checklist

- [ ] `Decimal` type class exists at `lib/clickhouse_ruby/types/decimal.rb`
  **prove:** `ruby -r./lib/clickhouse_ruby -e "ClickhouseRuby::Types::Decimal"`

- [ ] Parser handles `Decimal(18,4)` syntax
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/decimal_spec.rb --example "parses Decimal"`

- [ ] Parser handles `Decimal64(4)` shorthand syntax
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/decimal_spec.rb --example "parses Decimal64"`

- [ ] `cast()` converts Integer to BigDecimal
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/decimal_spec.rb --example "cast integer"`

- [ ] `cast()` converts Float to BigDecimal (with precision)
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/decimal_spec.rb --example "cast float"`

- [ ] `cast()` converts String to BigDecimal (preserving precision)
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/decimal_spec.rb --example "cast string"`

- [ ] `deserialize()` returns BigDecimal from ClickHouse response
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/decimal_spec.rb --example "deserialize"`

- [ ] `serialize()` formats BigDecimal for SQL without precision loss
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/decimal_spec.rb --example "serialize"`

- [ ] Validates precision doesn't exceed type limits
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/decimal_spec.rb --example "precision overflow"`

- [ ] Validates scale doesn't exceed precision
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/decimal_spec.rb --example "scale validation"`

- [ ] Registered in Types::Registry for Decimal, Decimal32, Decimal64, Decimal128, Decimal256
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/types/registry_spec.rb --example "Decimal"`

- [ ] Integration test: round-trip INSERT/SELECT preserves precision
  **prove:** `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec spec/integration/types_spec.rb --example "Decimal"`

- [ ] All unit tests pass
  **prove:** `bundle exec rake spec_unit`

- [ ] No lint errors
  **prove:** `bundle exec rake rubocop`

---

## Test Scenarios

```ruby
# spec/unit/clickhouse_ruby/types/decimal_spec.rb
RSpec.describe ClickhouseRuby::Types::Decimal do
  describe 'Decimal(18, 4)' do
    subject(:type) { described_class.new('Decimal(18, 4)') }

    it 'parses precision and scale' do
      expect(type.precision).to eq(18)
      expect(type.scale).to eq(4)
    end

    it 'determines internal type' do
      expect(type.internal_type).to eq(:Decimal64)
    end
  end

  describe 'Decimal64(4)' do
    subject(:type) { described_class.new('Decimal64(4)') }

    it 'uses max precision for variant' do
      expect(type.precision).to eq(18)
      expect(type.scale).to eq(4)
    end
  end

  describe '#cast' do
    subject(:type) { described_class.new('Decimal(10, 2)') }

    it 'converts integer' do
      expect(type.cast(42)).to eq(BigDecimal('42'))
    end

    it 'converts string preserving precision' do
      expect(type.cast('123.456789')).to eq(BigDecimal('123.456789'))
    end

    it 'raises on precision overflow' do
      # Decimal(10, 2) allows max 8 integer digits
      expect { type.cast('123456789.00') }
        .to raise_error(ClickhouseRuby::TypeCastError, /exceeds maximum integer digits/)
    end
  end

  describe '#serialize' do
    subject(:type) { described_class.new('Decimal(38, 18)') }

    it 'preserves high precision' do
      value = BigDecimal('123.456789012345678901234567890')
      serialized = type.serialize(value)
      expect(serialized).to include('123.456789012345678901234567890')
    end
  end
end
```

---

## References

- [ClickHouse Decimal Documentation](https://clickhouse.com/docs/en/sql-reference/data-types/decimal)
- [Ruby BigDecimal Documentation](https://ruby-doc.org/stdlib/libdoc/bigdecimal/rdoc/BigDecimal.html)
- [clickhouse-go Decimal Implementation](https://github.com/ClickHouse/clickhouse-go/blob/main/lib/column/decimal.go)
