# Type System Design

How ClickhouseRuby parses and converts ClickHouse types.

## Overview

The type system has three main components:

1. **Parser** - Converts type strings to AST
2. **Registry** - Maps type names to handler classes
3. **Type Classes** - Handle serialization/deserialization

## AST-Based Parser

Unlike regex-based parsers that fail on nested types, ClickhouseRuby uses a recursive descent parser:

```ruby
parser = ClickhouseRuby::Types::Parser.new

# Simple type
parser.parse('String')
# => { type: 'String' }

# Parameterized type
parser.parse('Nullable(String)')
# => { type: 'Nullable', args: [{ type: 'String' }] }

# Nested types (where regex fails)
parser.parse('Array(Tuple(String, UInt64))')
# => {
#      type: 'Array',
#      args: [{
#        type: 'Tuple',
#        args: [{ type: 'String' }, { type: 'UInt64' }]
#      }]
#    }

# Deeply nested
parser.parse('Map(String, Array(Nullable(UInt64)))')
# => handles any nesting depth correctly
```

### Why AST Matters

Other ClickHouse Ruby gems use regex:

```ruby
# Regex approach (breaks!)
type_string = 'Array(Tuple(String, UInt64))'
type_string.match(/^Array\((.+)\)$/)[1]
# => "Tuple(String, UInt64)"  # Can't parse further nested types
```

ClickhouseRuby's AST parser handles:
- Arbitrary nesting depth
- Multiple type arguments
- Parameterized types within parameterized types

## Type Registry

The registry maps ClickHouse type names to Ruby handler classes:

```ruby
registry = ClickhouseRuby::Types::Registry.new

# Lookup returns type handler
registry.lookup('String')       # => ClickhouseRuby::Types::String
registry.lookup('Array(UInt64)') # => ClickhouseRuby::Types::Array
```

### Registered Types

| ClickHouse | Handler Class |
|------------|--------------|
| String, FixedString | Types::String |
| Int8-Int64, UInt8-UInt64 | Types::Integer |
| Float32, Float64 | Types::Float |
| Date, Date32 | Types::Date |
| DateTime, DateTime64 | Types::DateTime |
| UUID | Types::UUID |
| Bool | Types::Boolean |
| Array | Types::Array |
| Map | Types::Map |
| Tuple | Types::Tuple |
| Nullable | Types::Nullable |
| LowCardinality | Types::LowCardinality |
| Enum8, Enum16 | Types::Enum |
| Decimal* | Types::Decimal |

## Type Class Interface

Each type class implements:

```ruby
class Types::Base
  # Convert Ruby value for ClickHouse query
  def serialize(value)
    # Ruby → SQL literal
  end

  # Convert ClickHouse value to Ruby
  def deserialize(value)
    # ClickHouse JSON → Ruby
  end

  # Cast Ruby value (validation)
  def cast(value)
    # Validate and normalize
  end
end
```

### Example: Array Type

```ruby
class Types::Array < Types::Base
  def initialize(element_type)
    @element_type = element_type
  end

  def serialize(value)
    elements = value.map { |v| @element_type.serialize(v) }
    "[#{elements.join(', ')}]"
  end

  def deserialize(value)
    value.map { |v| @element_type.deserialize(v) }
  end
end
```

## Data Flow

```
INSERT:
Ruby Value → Type.cast() → Type.serialize() → SQL String → ClickHouse

SELECT:
ClickHouse → JSON Response → Type.deserialize() → Ruby Value
```

### Insert Example

```ruby
# Ruby array
data = [1, 2, 3]

# Serialization
Types::Array.new(Types::Integer).serialize(data)
# => "[1, 2, 3]"

# Sent to ClickHouse
# INSERT INTO table (arr) VALUES ([1, 2, 3])
```

### Select Example

```ruby
# ClickHouse returns JSON
{"arr": [1, 2, 3]}

# Deserialization
Types::Array.new(Types::Integer).deserialize([1, 2, 3])
# => [1, 2, 3] (Ruby Array)
```

## Nullable Handling

The Nullable wrapper handles nil values:

```ruby
nullable_string = Types::Nullable.new(Types::String)

nullable_string.deserialize(nil)      # => nil
nullable_string.deserialize("hello")  # => "hello"

nullable_string.serialize(nil)        # => "NULL"
nullable_string.serialize("hello")    # => "'hello'"
```

## Complex Type Resolution

For nested types like `Map(String, Array(Nullable(UInt64)))`:

1. Parser creates AST
2. Registry recursively builds type handlers
3. Each level wraps the inner type

```ruby
# Simplified resolution
def resolve(ast)
  handler_class = registry.lookup(ast[:type])

  if ast[:args]
    inner_types = ast[:args].map { |a| resolve(a) }
    handler_class.new(*inner_types)
  else
    handler_class.new
  end
end
```

## See Also

- **[Types Reference](../reference/types.md)** - Type mapping table
- **[Architecture](architecture.md)** - Overall architecture
