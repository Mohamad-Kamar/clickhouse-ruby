# Installation

Get ClickhouseRuby installed and connected to ClickHouse.

## Install the Gem

Add to your `Gemfile`:

```ruby
gem 'clickhouse-ruby'
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install clickhouse-ruby
```

## Set Up ClickHouse

If you don't have ClickHouse running, start a local instance:

```bash
# Using Docker (recommended for development)
docker run -d -p 8123:8123 -p 9000:9000 clickhouse/clickhouse-server

# Or use docker-compose if available in project
docker-compose up -d
```

Verify ClickHouse is running:

```bash
curl http://localhost:8123
# Should return: Ok.
```

## Configure the Client

### Option 1: Block Configuration

```ruby
require 'clickhouse_ruby'

ClickhouseRuby.configure do |config|
  config.host = 'localhost'
  config.port = 8123
  config.database = 'default'
  config.username = 'default'
  config.password = ''
end

# Use the default client
client = ClickhouseRuby.client
```

### Option 2: Environment Variables

```bash
export CLICKHOUSE_HOST=localhost
export CLICKHOUSE_PORT=8123
export CLICKHOUSE_DATABASE=default
```

```ruby
require 'clickhouse_ruby'
client = ClickhouseRuby.client  # Auto-configured from ENV
```

### Option 3: Direct Configuration

```ruby
require 'clickhouse_ruby'

config = ClickhouseRuby::Configuration.new
config.host = 'localhost'
config.port = 8123

client = ClickhouseRuby::Client.new(config)
```

## Verify Connection

```ruby
client = ClickhouseRuby.client

# Basic check
client.ping  # => true

# Get server version
client.server_version  # => "24.1.1.123"

# Full health check (v0.3.0+)
health = client.health_check
puts health[:status]  # => :healthy
```

## Troubleshooting

### Connection Refused

```
ClickhouseRuby::ConnectionError: Connection refused
```

- Check if ClickHouse is running: `curl http://localhost:8123`
- Verify host and port settings
- Check firewall/network settings

### Authentication Failed

```
ClickhouseRuby::AuthenticationError: Authentication failed
```

- Verify username and password
- Check ClickHouse user permissions

### Timeout

```
ClickhouseRuby::ConnectionTimeout: Connection timed out
```

- Increase timeout: `config.connect_timeout = 30`
- Check network connectivity

## Next Steps

- **[First Query](first-query.md)** - Create tables and run queries
- **[Configuration Guide](../guides/configuration.md)** - All configuration options
