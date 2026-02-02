# Configuration Guide

Complete guide to configuring ClickhouseRuby for your application.

## Quick Configuration

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

## Configuration Options

### Connection Settings

| Option | Description | Default |
|--------|-------------|---------|
| `host` | ClickHouse server hostname | `localhost` |
| `port` | HTTP interface port | `8123` |
| `database` | Default database | `default` |
| `username` | Authentication username | `default` |
| `password` | Authentication password | `nil` |

### SSL/TLS Settings

| Option | Description | Default |
|--------|-------------|---------|
| `ssl` | Enable HTTPS | `false` |
| `ssl_verify` | Verify SSL certificates | `true` |
| `ssl_ca_path` | Custom CA certificate file path | `nil` |

**Security Note**: SSL verification is enabled by default for security. Only disable in development environments.

### Timeout Settings

| Option | Description | Default |
|--------|-------------|---------|
| `connect_timeout` | Connection timeout in seconds | `10` |
| `read_timeout` | Read timeout in seconds | `60` |
| `write_timeout` | Write timeout in seconds | `60` |

### Connection Pool Settings

| Option | Description | Default |
|--------|-------------|---------|
| `pool_size` | Connection pool size | `5` |
| `pool_timeout` | Wait time for available connection in seconds | `5` |

### Logging

| Option | Description | Default |
|--------|-------------|---------|
| `log_level` | Logger level (`:debug`, `:info`, `:warn`, `:error`) | `:info` |

### Performance Settings

| Option | Description | Default |
|--------|-------------|---------|
| `compression` | HTTP compression (`'gzip'` or `nil`) | `nil` |
| `compression_threshold` | Minimum payload size to compress (bytes) | `1024` |
| `max_retries` | Maximum retry attempts | `3` |
| `initial_backoff` | Initial backoff delay in seconds | `1.0` |
| `backoff_multiplier` | Backoff multiplier | `1.6` |
| `max_backoff` | Maximum backoff delay in seconds | `120.0` |
| `retry_jitter` | Jitter strategy (`:full`, `:equal`, `:none`) | `:equal` |
| `default_settings` | Global ClickHouse settings for all queries | `{}` |

## Environment Variables

ClickhouseRuby can be configured via environment variables:

```bash
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8123
CLICKHOUSE_DATABASE=default
CLICKHOUSE_USERNAME=default
CLICKHOUSE_PASSWORD=secret
CLICKHOUSE_SSL=false
```

Environment variables are automatically loaded when using `ClickhouseRuby.configure`.

## Multiple Clients

Create multiple clients for different ClickHouse instances:

```ruby
# Primary client
primary_config = ClickhouseRuby::Configuration.new
primary_config.host = 'clickhouse-primary.example.com'
primary_client = ClickhouseRuby::Client.new(primary_config)

# Replica client
replica_config = ClickhouseRuby::Configuration.new
replica_config.host = 'clickhouse-replica.example.com'
replica_client = ClickhouseRuby::Client.new(replica_config)
```

## Production Configuration Example

```ruby
ClickhouseRuby.configure do |config|
  # Connection
  config.host = ENV['CLICKHOUSE_HOST'] || 'localhost'
  config.port = ENV['CLICKHOUSE_PORT']&.to_i || 8123
  config.database = ENV['CLICKHOUSE_DATABASE'] || 'analytics'
  config.username = ENV['CLICKHOUSE_USERNAME'] || 'default'
  config.password = ENV['CLICKHOUSE_PASSWORD']
  
  # SSL
  config.ssl = ENV['CLICKHOUSE_SSL'] == 'true'
  config.ssl_verify = true  # Always verify in production
  
  # Timeouts
  config.connect_timeout = 10
  config.read_timeout = 300  # Longer for complex queries
  config.write_timeout = 300
  
  # Pool
  config.pool_size = 10  # More connections for high concurrency
  config.pool_timeout = 5
  
  # Performance
  config.compression = 'gzip'
  config.compression_threshold = 1024
  config.max_retries = 3
  config.initial_backoff = 1.0
  config.backoff_multiplier = 2.0
  config.max_backoff = 60
  
  # Logging
  config.log_level = ENV['LOG_LEVEL']&.to_sym || :info
  
  # Global ClickHouse settings
  config.default_settings = {
    max_execution_time: 300,
    max_threads: 4
  }
end
```

## Configuration Best Practices

1. **Use environment variables** for sensitive data (passwords, hosts)
2. **Enable SSL** in production environments
3. **Set appropriate timeouts** based on your query patterns
4. **Tune pool size** based on concurrent request patterns
5. **Enable compression** for large payloads (>1KB)
6. **Configure retries** for transient failures
7. **Use default_settings** for global query optimizations

See [docs/ADVANCED_FEATURES.md](ADVANCED_FEATURES.md) for advanced configuration patterns.
