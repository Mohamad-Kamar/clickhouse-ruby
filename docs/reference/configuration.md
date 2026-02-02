# Configuration Reference

All configuration options for ClickhouseRuby.

## Connection Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `host` | String | `localhost` | ClickHouse server hostname |
| `port` | Integer | `8123` | HTTP interface port |
| `database` | String | `default` | Default database |
| `username` | String | `default` | Authentication username |
| `password` | String | `nil` | Authentication password |

## SSL Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ssl` | Boolean | `false` | Enable HTTPS |
| `ssl_verify` | Boolean | `true` | Verify SSL certificates |
| `ssl_ca_path` | String | `nil` | Custom CA certificate file path |

## Timeout Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `connect_timeout` | Integer | `10` | Connection timeout (seconds) |
| `read_timeout` | Integer | `60` | Read timeout (seconds) |
| `write_timeout` | Integer | `60` | Write timeout (seconds) |

## Pool Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pool_size` | Integer | `5` | Connection pool size |
| `pool_timeout` | Integer | `5` | Wait time for available connection (seconds) |

## Performance Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `compression` | String | `nil` | Compression algorithm (`'gzip'` or `nil`) |
| `compression_threshold` | Integer | `1024` | Minimum payload size to compress (bytes) |

## Retry Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `max_retries` | Integer | `3` | Maximum retry attempts |
| `initial_backoff` | Float | `1.0` | Initial backoff delay (seconds) |
| `backoff_multiplier` | Float | `1.6` | Backoff multiplier |
| `max_backoff` | Float | `120.0` | Maximum backoff delay (seconds) |
| `retry_jitter` | Symbol | `:equal` | Jitter strategy (`:full`, `:equal`, `:none`) |

## Other Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `log_level` | Symbol | `:info` | Logger level (`:debug`, `:info`, `:warn`, `:error`) |
| `default_settings` | Hash | `{}` | Global ClickHouse settings for all queries |

## Environment Variables

| Variable | Maps To |
|----------|---------|
| `CLICKHOUSE_HOST` | `host` |
| `CLICKHOUSE_PORT` | `port` |
| `CLICKHOUSE_DATABASE` | `database` |
| `CLICKHOUSE_USERNAME` | `username` |
| `CLICKHOUSE_PASSWORD` | `password` |
| `CLICKHOUSE_SSL` | `ssl` |

## Example Configurations

### Development

```ruby
ClickhouseRuby.configure do |config|
  config.host = 'localhost'
  config.port = 8123
  config.database = 'development'
end
```

### Production

```ruby
ClickhouseRuby.configure do |config|
  config.host = ENV['CLICKHOUSE_HOST']
  config.port = ENV['CLICKHOUSE_PORT']
  config.database = ENV['CLICKHOUSE_DATABASE']
  config.username = ENV['CLICKHOUSE_USERNAME']
  config.password = ENV['CLICKHOUSE_PASSWORD']
  config.ssl = true
  config.ssl_verify = true
  config.pool_size = 20
  config.read_timeout = 120
  config.compression = 'gzip'
  config.max_retries = 3
end
```

### Multiple Clients

```ruby
# Primary cluster
primary_config = ClickhouseRuby::Configuration.new
primary_config.host = 'primary.clickhouse.example.com'
primary_client = ClickhouseRuby::Client.new(primary_config)

# Analytics cluster
analytics_config = ClickhouseRuby::Configuration.new
analytics_config.host = 'analytics.clickhouse.example.com'
analytics_client = ClickhouseRuby::Client.new(analytics_config)
```

## See Also

- **[Configuration Guide](../guides/configuration.md)** - How to configure
- **[Production Guide](../guides/production.md)** - Production settings
