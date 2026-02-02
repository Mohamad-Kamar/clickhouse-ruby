# Type Mapping Reference

ClickHouse to Ruby type mappings.

## Basic Types

| ClickHouse Type | Ruby Type | Notes |
|-----------------|-----------|-------|
| `Int8` | Integer | -128 to 127 |
| `Int16` | Integer | -32,768 to 32,767 |
| `Int32` | Integer | -2B to 2B |
| `Int64` | Integer | Full 64-bit range |
| `UInt8` | Integer | 0 to 255 |
| `UInt16` | Integer | 0 to 65,535 |
| `UInt32` | Integer | 0 to 4B |
| `UInt64` | Integer | 0 to 18Q |
| `Float32` | Float | Single precision |
| `Float64` | Float | Double precision |
| `String` | String | Variable length |
| `FixedString(N)` | String | Fixed N bytes |
| `UUID` | String | 36-char UUID string |
| `Bool` | Boolean | `true`/`false` |

## Date/Time Types

| ClickHouse Type | Ruby Type | Notes |
|-----------------|-----------|-------|
| `Date` | Date | Days since epoch |
| `Date32` | Date | Extended range |
| `DateTime` | Time | Seconds precision |
| `DateTime64(N)` | Time | Sub-second precision |

## Complex Types

| ClickHouse Type | Ruby Type | Example |
|-----------------|-----------|---------|
| `Nullable(T)` | T or `nil` | `Nullable(String)` → String or nil |
| `Array(T)` | Array | `Array(UInt64)` → [1, 2, 3] |
| `Map(K, V)` | Hash | `Map(String, Int32)` → {"a" => 1} |
| `Tuple(T1, T2, ...)` | Array | `Tuple(String, Int32)` → ["a", 1] |
| `LowCardinality(T)` | T | Transparent wrapper |

## Advanced Types

| ClickHouse Type | Ruby Type | Notes |
|-----------------|-----------|-------|
| `Enum8('a'=1,'b'=2)` | String | Maps string ↔ integer |
| `Enum16('a'=1,'b'=2)` | String | Up to 65K values |
| `Decimal(P,S)` | BigDecimal | Arbitrary precision |
| `Decimal32(S)` | BigDecimal | Up to 9 digits |
| `Decimal64(S)` | BigDecimal | Up to 18 digits |
| `Decimal128(S)` | BigDecimal | Up to 38 digits |
| `Decimal256(S)` | BigDecimal | Up to 76 digits |

## Type Parsing

ClickhouseRuby uses an AST-based parser that handles nested types:

```ruby
# All these parse correctly
parser = ClickhouseRuby::Types::Parser.new

parser.parse('Array(UInt64)')
# => { type: 'Array', args: [{ type: 'UInt64' }] }

parser.parse('Map(String, Array(UInt64))')
# => { type: 'Map', args: [
#      { type: 'String' },
#      { type: 'Array', args: [{ type: 'UInt64' }] }
#    ]}

parser.parse('Tuple(String, Nullable(Int32), Array(Float64))')
# => handles arbitrarily complex nesting
```

## Ruby to ClickHouse Serialization

| Ruby Type | ClickHouse Type | Serialized As |
|-----------|-----------------|---------------|
| Integer | Int*/UInt* | Number literal |
| Float | Float* | Number literal |
| String | String | Quoted string |
| Date | Date | `'2024-01-15'` |
| Time | DateTime | `'2024-01-15 10:30:00'` |
| BigDecimal | Decimal | Exact decimal string |
| Array | Array | `[1, 2, 3]` |
| Hash | Map | `{'key': 'value'}` |
| nil | Nullable | `NULL` |
| true/false | Bool | `1`/`0` |

## Type Gotchas

### Enum

- Values must be predefined in table schema
- Cannot insert unknown values
- String display, integer storage

### Decimal

- Use BigDecimal in Ruby, not Float
- Scale cannot exceed precision
- Precision limited by type variant

### DateTime64

- Sub-second precision depends on type parameter
- `DateTime64(3)` = milliseconds
- `DateTime64(6)` = microseconds

### Nullable

- Adds storage overhead
- Use only when NULL is meaningful
- Default values preferred when possible

## See Also

- **[Enum Type Guide](../guides/activerecord.md)** - Working with enums
- **[Decimal Type Guide](../guides/activerecord.md)** - Financial data
