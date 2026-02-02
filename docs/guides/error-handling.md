# Error Handling

How to handle errors gracefully with ClickhouseRuby.

## Basic Error Handling

```ruby
begin
  client.execute('SELECT * FROM nonexistent_table')
rescue ClickhouseRuby::UnknownTable => e
  puts "Table not found: #{e.message}"
  puts "Error code: #{e.code}"        # ClickHouse error code
  puts "HTTP status: #{e.http_status}" # HTTP response code
rescue ClickhouseRuby::ConnectionError => e
  puts "Connection failed: #{e.message}"
rescue ClickhouseRuby::QueryError => e
  puts "Query failed: #{e.message}"
  puts "SQL: #{e.sql}"                # The SQL that failed
end
```

## Error Hierarchy

```
ClickhouseRuby::Error (base class)
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
│   └── UnknownDatabase
├── TypeCastError
├── ConfigurationError
└── PoolError
    ├── PoolExhausted
    └── PoolTimeout
```

## Common Errors

### Connection Errors

```ruby
begin
  client.execute('SELECT 1')
rescue ClickhouseRuby::ConnectionNotEstablished => e
  # Server not reachable
  puts "Cannot connect: #{e.message}"
  # Check: host, port, firewall
rescue ClickhouseRuby::ConnectionTimeout => e
  # Connection timed out
  puts "Timeout: #{e.message}"
  # Solution: increase connect_timeout
rescue ClickhouseRuby::SSLError => e
  # SSL/TLS issue
  puts "SSL error: #{e.message}"
  # Check: ssl_verify, ssl_ca_path settings
end
```

### Query Errors

```ruby
begin
  client.execute(sql)
rescue ClickhouseRuby::SyntaxError => e
  # SQL syntax error
  puts "Invalid SQL: #{e.message}"
rescue ClickhouseRuby::UnknownTable => e
  # Table doesn't exist
  puts "Table not found: #{e.message}"
rescue ClickhouseRuby::UnknownColumn => e
  # Column doesn't exist
  puts "Column not found: #{e.message}"
rescue ClickhouseRuby::QueryTimeout => e
  # Query took too long
  puts "Query timeout: #{e.message}"
  # Solution: increase read_timeout or optimize query
end
```

### Pool Errors

```ruby
begin
  client.execute('SELECT 1')
rescue ClickhouseRuby::PoolExhausted => e
  # No connections available
  puts "Pool exhausted: #{e.message}"
  # Solution: increase pool_size or pool_timeout
rescue ClickhouseRuby::PoolTimeout => e
  # Waited too long for connection
  puts "Pool timeout: #{e.message}"
end
```

## Error Attributes

All errors include helpful attributes:

```ruby
begin
  client.execute('SELECT * FROM bad_table')
rescue ClickhouseRuby::QueryError => e
  e.message      # Human-readable message
  e.code         # ClickHouse error code (e.g., 60 for UNKNOWN_TABLE)
  e.http_status  # HTTP status (e.g., "404")
  e.sql          # The SQL that failed
end
```

## Retry Patterns

### Simple Retry

```ruby
def with_retry(max_attempts: 3)
  attempts = 0
  begin
    yield
  rescue ClickhouseRuby::ConnectionError => e
    attempts += 1
    if attempts < max_attempts
      sleep(2 ** attempts)  # Exponential backoff
      retry
    end
    raise
  end
end

with_retry { client.execute('SELECT 1') }
```

### Built-in Retry

Configure automatic retries:

```ruby
ClickhouseRuby.configure do |config|
  config.max_retries = 3
  config.initial_backoff = 1.0
  config.backoff_multiplier = 1.6
  config.max_backoff = 120
  config.retry_jitter = :equal
end
```

**Automatically retries:**
- ConnectionError (network issues)
- Timeout errors
- HTTP 5xx errors
- HTTP 429 (rate limit)

**Does NOT retry:**
- QueryError (syntax errors, invalid SQL)
- HTTP 4xx errors (client errors)

## Health Checks

Check system health before operations:

```ruby
health = client.health_check

if health[:status] != :healthy
  puts "System unhealthy!"
  puts "Server reachable: #{health[:server_reachable]}"
  puts "Pool: #{health[:pool]}"
end
```

## Rails Integration

In Rails controllers:

```ruby
class EventsController < ApplicationController
  rescue_from ClickhouseRuby::ConnectionError do |e|
    render json: { error: 'Database unavailable' }, status: 503
  end

  rescue_from ClickhouseRuby::QueryError do |e|
    Rails.logger.error("Query failed: #{e.message}")
    render json: { error: 'Query failed' }, status: 500
  end

  def index
    @events = Event.where(user_id: current_user.id).limit(100)
  end
end
```

## Logging Errors

```ruby
begin
  client.execute(sql)
rescue ClickhouseRuby::Error => e
  Rails.logger.error({
    error: e.class.name,
    message: e.message,
    code: e.respond_to?(:code) ? e.code : nil,
    sql: e.respond_to?(:sql) ? e.sql : nil
  }.to_json)
  raise
end
```

## See Also

- **[Configuration Guide](configuration.md)** - Configure timeouts and retries
- **[Production Guide](production.md)** - Production error handling patterns
- **[Reference: Error Codes](../reference/errors.md)** - Complete error code list
