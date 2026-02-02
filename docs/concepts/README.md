# Concepts

Understanding ClickhouseRuby's architecture and design.

## Concept Documents

| Document | Description |
|----------|-------------|
| [Architecture](architecture.md) | Internal architecture and design decisions |
| [Performance](performance.md) | Performance concepts and tuning strategies |
| [Type System](type-system.md) | How types are parsed and converted |

## Key Design Principles

### 1. Security by Default

- SSL verification enabled by default
- Never silently fail on errors
- Proper authentication handling

### 2. Zero Runtime Dependencies

- Uses only Ruby stdlib
- Fully auditable codebase
- No external gems required

### 3. AST-Based Type Parsing

- Handles complex nested types correctly
- `Array(Tuple(String, UInt64))` works properly
- Unlike regex-based parsers in other gems

### 4. Thread-Safe by Design

- Connection pooling with proper synchronization
- Health checks before returning connections
- Safe for multi-threaded applications

## See Also

- **[Getting Started](../getting-started/)** - Tutorials
- **[Guides](../guides/)** - How-to guides
- **[Reference](../reference/)** - API reference
