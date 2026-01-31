# ClickhouseRuby

A lightweight Ruby client for ClickHouse with optional ActiveRecord integration.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'clickhouse-ruby'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install clickhouse-ruby
```

## Quick Start

```ruby
require 'clickhouse-ruby'

# Create a client
client = ClickhouseRuby::Client.new(
  host: 'localhost',
  port: 8123,
  database: 'default'
)

# Execute a query
result = client.query('SELECT 1 + 1 AS result')
puts result.first['result'] # => 2

# Insert data
client.insert('events', [
  { date: '2024-01-01', event_type: 'click', count: 100 },
  { date: '2024-01-02', event_type: 'view', count: 250 }
])
```

## Configuration

### Basic Configuration

```ruby
ClickhouseRuby.configure do |config|
  config.host = 'localhost'
  config.port = 8123
  config.database = 'default'
  config.username = 'default'
  config.password = ''
  config.ssl = false
  config.timeout = 60
end

# Use the default client
client = ClickhouseRuby.client
```

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `host` | ClickHouse server hostname | `localhost` |
| `port` | HTTP interface port | `8123` |
| `database` | Default database | `default` |
| `username` | Authentication username | `default` |
| `password` | Authentication password | `''` |
| `ssl` | Enable HTTPS | `false` |
| `timeout` | Request timeout in seconds | `60` |
| `max_retries` | Number of retry attempts | `3` |

### Environment Variables

ClickhouseRuby can be configured via environment variables:

```bash
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8123
CLICKHOUSE_DATABASE=default
CLICKHOUSE_USERNAME=default
CLICKHOUSE_PASSWORD=secret
CLICKHOUSE_SSL=false
```

## Usage

### Querying Data

```ruby
# Simple query
result = client.query('SELECT * FROM events LIMIT 10')

# Query with parameters (prevents SQL injection)
result = client.query(
  'SELECT * FROM events WHERE date = {date:Date}',
  params: { date: '2024-01-01' }
)

# Query with specific format
result = client.query('SELECT * FROM events', format: 'JSONEachRow')
```

### Inserting Data

```ruby
# Insert hash array
client.insert('events', [
  { date: '2024-01-01', event_type: 'click', count: 100 },
  { date: '2024-01-02', event_type: 'view', count: 250 }
])

# Insert with explicit columns
client.insert('events', data, columns: [:date, :event_type, :count])

# Bulk insert from CSV
client.insert_from_file('events', '/path/to/data.csv', format: 'CSV')
```

### DDL Operations

```ruby
# Create table
client.execute(<<~SQL)
  CREATE TABLE events (
    date Date,
    event_type String,
    count UInt32
  ) ENGINE = MergeTree()
  ORDER BY date
SQL

# Check if table exists
client.table_exists?('events') # => true

# Get table schema
schema = client.describe_table('events')
```

### Connection Management

```ruby
# Check connection
client.ping # => true

# Get server version
client.server_version # => "24.1.1.123"

# Execute multiple queries in a session
client.with_session do |session|
  session.execute('SET max_memory_usage = 1000000000')
  session.query('SELECT * FROM large_table')
end
```

## ActiveRecord Integration

ClickhouseRuby provides optional ActiveRecord integration for familiar model-based access.

```ruby
# config/initializers/clickhouse-ruby.rb
require 'clickhouse-ruby/active_record'

ClickhouseRuby::ActiveRecord.establish_connection(
  host: 'localhost',
  database: 'analytics'
)

# app/models/event.rb
class Event < ClickhouseRuby::ActiveRecord::Base
  self.table_name = 'events'
end

# Usage
Event.where(date: '2024-01-01').limit(10).each do |event|
  puts event.event_type
end
```

## Error Handling

```ruby
begin
  client.query('SELECT * FROM nonexistent_table')
rescue ClickhouseRuby::ConnectionError => e
  # Handle connection issues
  puts "Connection failed: #{e.message}"
rescue ClickhouseRuby::QueryError => e
  # Handle query errors
  puts "Query failed: #{e.message}"
  puts "Error code: #{e.code}"
rescue ClickhouseRuby::TimeoutError => e
  # Handle timeouts
  puts "Request timed out: #{e.message}"
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

### Running Tests

```bash
# Start ClickHouse
docker-compose up -d

# Run all tests
bundle exec rake spec

# Run only unit tests
bundle exec rake spec_unit

# Run integration tests
bundle exec rake spec_integration
```

### Code Quality

```bash
# Run RuboCop
bundle exec rake rubocop

# Auto-fix issues
bundle exec rake rubocop_fix
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yourusername/clickhouse-ruby.

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).

## Documentation

Full documentation is available at [RubyDoc](https://rubydoc.info/gems/clickhouse-ruby).
