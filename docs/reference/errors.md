# Error Reference

Complete list of ClickhouseRuby error classes and ClickHouse error codes.

## Error Hierarchy

```
ClickhouseRuby::Error
├── ConnectionError
│   ├── ConnectionNotEstablished
│   ├── ConnectionTimeout
│   └── SSLError
├── QueryError
│   ├── StatementInvalid
│   ├── SyntaxError
│   ├── QueryTimeout
│   ├── UnknownTable
│   ├── UnknownColumn
│   ├── UnknownDatabase
│   └── AuthenticationError
├── TypeCastError
├── ConfigurationError
└── PoolError
    ├── PoolExhausted
    └── PoolTimeout
```

## Error Classes

### Base Error

| Class | Description |
|-------|-------------|
| `ClickhouseRuby::Error` | Base class for all errors |

### Connection Errors

| Class | Description | Common Causes |
|-------|-------------|---------------|
| `ConnectionError` | Base connection error | Network issues |
| `ConnectionNotEstablished` | Cannot connect to server | Wrong host/port, server down |
| `ConnectionTimeout` | Connection timed out | Network latency, firewall |
| `SSLError` | SSL/TLS error | Certificate issues, SSL config |

### Query Errors

| Class | Description | Common Causes |
|-------|-------------|---------------|
| `QueryError` | Base query error | Various query issues |
| `StatementInvalid` | Invalid SQL statement | Malformed query |
| `SyntaxError` | SQL syntax error | Typos, wrong syntax |
| `QueryTimeout` | Query execution timeout | Slow query, low timeout |
| `UnknownTable` | Table doesn't exist | Typo, wrong database |
| `UnknownColumn` | Column doesn't exist | Typo, schema change |
| `UnknownDatabase` | Database doesn't exist | Wrong database name |
| `AuthenticationError` | Authentication failed | Wrong credentials |

### Other Errors

| Class | Description | Common Causes |
|-------|-------------|---------------|
| `TypeCastError` | Type conversion failed | Invalid data for type |
| `ConfigurationError` | Invalid configuration | Wrong config values |
| `PoolExhausted` | No connections available | Pool too small, connection leak |
| `PoolTimeout` | Timeout waiting for connection | Pool contention |

## Error Attributes

All errors provide these attributes when available:

```ruby
begin
  client.execute('SELECT * FROM bad_table')
rescue ClickhouseRuby::QueryError => e
  e.message      # String - Human-readable message
  e.code         # Integer - ClickHouse error code
  e.http_status  # String - HTTP status code
  e.sql          # String - The SQL that failed
end
```

## ClickHouse Error Codes

Common ClickHouse error codes mapped to exceptions:

| Code | Name | ClickhouseRuby Class |
|------|------|---------------------|
| 60 | UNKNOWN_TABLE | `UnknownTable` |
| 16 | UNKNOWN_COLUMN | `UnknownColumn` |
| 81 | UNKNOWN_DATABASE | `UnknownDatabase` |
| 62 | SYNTAX_ERROR | `SyntaxError` |
| 159 | TIMEOUT_EXCEEDED | `QueryTimeout` |
| 516 | AUTHENTICATION_FAILED | `AuthenticationError` |

## Retriable vs Non-Retriable

### Retriable Errors

These errors may succeed on retry:

- `ConnectionError` (network issues)
- `ConnectionTimeout` (transient timeout)
- HTTP 5xx errors (server issues)
- HTTP 429 (rate limit)

### Non-Retriable Errors

These errors will not succeed on retry:

- `SyntaxError` (fix the SQL)
- `UnknownTable` (create the table)
- `UnknownColumn` (fix the column name)
- `TypeCastError` (fix the data)
- HTTP 4xx errors (client errors)

## See Also

- **[Error Handling Guide](../guides/error-handling.md)** - How to handle errors
- **[Configuration Reference](configuration.md)** - Retry settings
