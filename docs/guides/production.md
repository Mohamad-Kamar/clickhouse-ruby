# Production Guide

This guide covers production deployment considerations, connection pool management, monitoring, and configuration best practices for ClickhouseRuby in production environments.

## Table of Contents

1. [Pool Management](#pool-management)
2. [Production Configuration](#production-configuration)
3. [Health Monitoring](#health-monitoring)
4. [Monitoring Integration](#monitoring-integration)
5. [Best Practices](#best-practices)

---

## Pool Management

The connection pool is the foundation of ClickhouseRuby's performance. Understanding pool lifecycle, monitoring, and tuning is critical for production applications.

### Connection Pool Lifecycle

Each Client maintains its own ConnectionPool instance. The pool manages a fixed-size set of HTTP connections (default: 5 connections) to the ClickHouse server.

```ruby
config = ClickhouseRuby::Configuration.new
config.host = 'clickhouse.example.com'
config.pool_size = 10      # Number of connections to maintain
config.pool_timeout = 5    # Seconds to wait for a connection

client = ClickhouseRuby::Client.new(config)

# Connections are checked out for each query
result = client.execute('SELECT 1')  # Checkout, query, checkin
result = client.execute('SELECT 2')  # Reuse same connection
```

The pool automatically creates connections on-demand up to `pool_size`. When all connections are in-use, subsequent queries block until a connection becomes available or `pool_timeout` seconds elapse.

### Health Checks and Monitoring

Monitor pool health using `pool_stats` and `health_check`:

```ruby
# Get current pool statistics
stats = client.pool_stats
# => {
#   size: 5,           # Total pool capacity
#   available: 3,      # Currently idle connections
#   in_use: 2,         # Currently active connections
#   total_created: 12, # Lifetime connections created
#   failed_checks: 1   # Lifetime failed health checks
# }

# Verify all connections are healthy
client.pool.health_check
# Returns nil if healthy, raises exception if check fails
```

Use `pool_stats` in health check endpoints and dashboards:

```ruby
# In a Rails health check endpoint
get '/health/pool' do
  stats = client.pool_stats
  if stats[:available] > 0
    json({ status: 'ok', pool: stats })
  else
    json({ status: 'warning', pool: stats }, status: 503)
  end
end
```

### Comprehensive Health Check

Beyond basic `pool_stats`, comprehensive health monitoring:

```ruby
# Complete system status - all components checked
health = client.health_check
# => {
#   status: :healthy,                    # :healthy or :unhealthy
#   server_reachable: true,              # Can reach ClickHouse server
#   server_version: "24.1.1.123",        # ClickHouse version
#   current_database: "default",        # Current database name
#   server_uptime_seconds: 3600,         # Server uptime in seconds
#   pool: {                              # Connection pool health
#     available: 3,                     # Available connections
#     in_use: 2,                        # Connections in use
#     total: 5,                         # Total connections
#     capacity: 5,                      # Pool capacity
#     healthy: 3,                       # Healthy connections
#     unhealthy: 0                      # Unhealthy connections
#   },
#   check_duration_ms: 12.5             # Health check duration
# }

# Monitoring integration example
class HealthController
  def status
    health = client.health_check
    if health[:status] == :healthy && health[:pool][:available] > 0
      render json: { status: 'ok' }
    else
      render json: { status: 'degraded', details: health }
    end
  end
end

# Pool health detection
health[:pool][:healthy] < health[:pool][:total] # Indicates connection issues
```

### Idle Connection Cleanup

Long-running applications should periodically clean up idle connections to reclaim system resources and refresh connections that may have gone stale:

```ruby
# Remove idle connections older than 5 minutes
client.pool.cleanup(max_idle_seconds: 300)

# Run cleanup every 10 minutes in a background job
class PoolCleanupJob
  include Sidekiq::Job

  sidekiq_options retry: 0

  def perform
    client = ClickhouseRuby.client
    removed_count = client.pool.cleanup(max_idle_seconds: 300)
    logger.info("Pool cleanup: removed #{removed_count} idle connections")
  rescue => e
    logger.error("Pool cleanup failed: #{e.message}")
  end
end
```

### Thread-Safety Guarantees

The connection pool is thread-safe and designed for concurrent access. Each thread gets its own connection from the pool:

```ruby
# Thread-safe usage in a Rails controller
class EventsController < ApplicationController
  def track
    client = ClickhouseRuby.client
    # Each request thread gets its own connection from the pool
    client.insert('events', event_params)
    render json: { status: 'ok' }
  end
end

# Thread-safe usage in Sidekiq workers
class EventProcessor
  include Sidekiq::Worker

  def perform(event_id)
    client = ClickhouseRuby.client
    event = Event.find(event_id)
    # Worker thread gets a connection from the shared pool
    client.insert('processed_events', format_event(event))
  end
end
```

All pool operations use Mutex synchronization internally. The `with_connection` method provides explicit control:

```ruby
# Manual connection management with explicit block
client.pool.with_connection do |conn|
  response = conn.execute('SELECT 1')
  puts response.body
end
# Connection automatically checked back in
```

### Pool Exhaustion and Tuning

Pool exhaustion occurs when all connections are in-use and a new query arrives. Symptoms include:

- Timeout exceptions: `Timeout::Error` or `ClickhouseRuby::PoolError`
- Increased P99 latency
- Queue buildup in logs

Tuning strategies:

```ruby
# Strategy 1: Increase pool size for high concurrency
config.pool_size = 20        # For 16+ concurrent requests

# Strategy 2: Reduce query time to free connections faster
# - Add indexes, optimize queries, use PREWHERE
# - Lower max_execution_time in settings if queries stall

# Strategy 3: Reduce pool_timeout to fail fast
config.pool_timeout = 1      # Fail quickly instead of blocking

# Strategy 4: Use multiple clients for read/write separation
read_client = ClickhouseRuby::Client.new(read_config)
write_client = ClickhouseRuby::Client.new(write_config)
```

### Common Gotchas

**Gotcha 1: Pool Leaks from Exceptions**

If an exception occurs during query execution, ensure the connection is returned:

```ruby
# BAD: Connection may not be returned if exception occurs
result = client.with_connection { |conn| conn.execute('...') }

# GOOD: Automatic cleanup with public API
result = client.execute('...')

# GOOD: Explicit try-finally if needed
begin
  result = client.with_connection { |conn| conn.execute('...') }
rescue => e
  # Connection is returned even if exception occurs
  raise
end
```

**Gotcha 2: Per-Process vs Shared Pool**

Each Client instance has its own pool. In a Rails app with N processes, you have N pools. This is intentional but affects resource usage:

```ruby
# Each process has separate pool (N × pool_size connections total)
# In a 4-process server with pool_size=5: 20 total connections
ClickhouseRuby.configure { |c| c.pool_size = 5 }

# Solution: Use single shared client per process
ClickhouseRuby.configure do |config|
  config.host = 'clickhouse.example.com'
  config.pool_size = 10  # Per-process, so 40 total in 4-process server
end

in_initializer :clickhouse do
  ClickhouseRuby.ensure_client # Create shared instance
end
```

**Gotcha 3: Blocking on Connection Checkout**

Long `pool_timeout` values can degrade response times under load:

```ruby
# BAD: Block for 30 seconds if pool exhausted (very bad UX)
config.pool_timeout = 30

# GOOD: Fail fast and respond quickly
config.pool_timeout = 2    # Rails default is 5 seconds
config.pool_size = 20      # Increase capacity instead
```

---

## Production Configuration

### Configuration Validation

Validate configuration before creating a client:

```ruby
config = ClickhouseRuby::Configuration.new
config.host = 'clickhouse.example.com'
config.port = 8443
config.ssl = true
config.ssl_verify = true

# Validate all settings
config.validate!  # Raises ConfigurationError if invalid

# Common validation checks:
# - Host is not empty
# - Port is 1-65535
# - Timeouts are positive
# - Pool size is > 0

# Usage in initialization
begin
  config.validate!
  client = ClickhouseRuby::Client.new(config)
rescue ClickhouseRuby::ConfigurationError => e
  logger.error("Invalid configuration: #{e.message}")
  exit 1
end
```

### SSL/TLS Configuration

Configure SSL with helpers:

```ruby
# Automatic SSL detection based on port
config = ClickhouseRuby::Configuration.new
config.port = 8443
config.use_ssl?  # => true (automatically detected)

# Check if SSL is enabled
if config.use_ssl?
  logger.info("SSL enabled: #{config.ssl_ca_path || 'system defaults'}")
end

# Set custom CA certificate
config.ssl_ca_path = '/etc/ssl/certs/custom-ca.pem'
config.ssl_verify = true

# Ensure certificate verification (always verify in production)
config.ssl_verify = ENV['CLICKHOUSE_SKIP_SSL_VERIFICATION'] != 'true'
```

### Production Configuration Example

```ruby
ClickhouseRuby.configure do |config|
  # Connection
  config.host = ENV['CLICKHOUSE_HOST'] || 'localhost'
  config.port = ENV['CLICKHOUSE_PORT']&.to_i || 8123
  config.database = ENV['CLICKHOUSE_DATABASE'] || 'analytics'
  config.username = ENV['CLICKHOUSE_USERNAME'] || 'default'
  config.password = ENV['CLICKHOUSE_PASSWORD']
  
  # SSL (always enabled in production)
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

### Configuration Cloning for Multiple Clients

Create variations of configuration for different purposes:

```ruby
# Base configuration
base_config = ClickhouseRuby::Configuration.new
base_config.host = ENV['CLICKHOUSE_HOST']
base_config.port = ENV['CLICKHOUSE_PORT'].to_i
base_config.database = 'default'
base_config.pool_size = 10

# Clone for read-only replica with different settings
read_config = base_config.dup
read_config.host = ENV['CLICKHOUSE_REPLICA_HOST']
read_config.pool_size = 20  # More connections for reads

# Clone for writes with higher timeout
write_config = base_config.dup
write_config.write_timeout = 120  # Longer timeout for writes

# Use appropriately
read_client = ClickhouseRuby::Client.new(read_config)
write_client = ClickhouseRuby::Client.new(write_config)
```

### Pool and Timeout Settings

Critical for production stability:

```ruby
# Connection limits
config.pool_size = 10         # Concurrent connections
config.pool_timeout = 5       # Wait for available connection

# Socket timeouts (in seconds)
config.connect_timeout = 10   # Establish connection
config.read_timeout = 60      # Wait for response
config.write_timeout = 60     # Send request

# For slow queries or large result sets
config.read_timeout = 300     # 5 minutes for streaming

# For high-latency networks
config.connect_timeout = 30   # Up to 30 seconds to connect
config.read_timeout = 120     # Up to 2 minutes for responses
```

---

## Health Monitoring

### Health Check Endpoints

Create health check endpoints for monitoring systems:

```ruby
# Rails health check endpoint
class HealthController < ApplicationController
  def show
    health = ClickhouseRuby.client.health_check
    
    if health[:status] == :healthy && health[:pool][:available] > 0
      render json: {
        status: 'ok',
        clickhouse: {
          server_version: health[:server_version],
          database: health[:current_database],
          pool: health[:pool]
        }
      }
    else
      render json: {
        status: 'degraded',
        clickhouse: health
      }, status: 503
    end
  end
end
```

### Monitoring Pool Health

Track pool metrics over time:

```ruby
# Periodic pool health check
class PoolHealthMonitor
  def self.check
    stats = ClickhouseRuby.client.pool_stats
    health = ClickhouseRuby.client.health_check
    
    metrics = {
      pool_size: stats[:size],
      pool_available: stats[:available],
      pool_in_use: stats[:in_use],
      pool_healthy: health[:pool][:healthy],
      pool_unhealthy: health[:pool][:unhealthy]
    }
    
    # Alert if pool is exhausted
    if stats[:available] == 0
      alert("Pool exhausted: #{stats}")
    end
    
    # Alert if unhealthy connections detected
    if health[:pool][:unhealthy] > 0
      alert("Unhealthy connections: #{health[:pool][:unhealthy]}")
    end
    
    metrics
  end
end
```

---

## Monitoring Integration

### Instrumentation

ClickhouseRuby provides comprehensive instrumentation via ActiveSupport::Notifications. See [Advanced Features - Observability & Instrumentation](ADVANCED_FEATURES.md#8-observability--instrumentation) for complete details.

### APM Integration

Integrate with APM tools for production monitoring:

```ruby
# New Relic integration
ActiveSupport::Notifications.subscribe('clickhouse_ruby.query.complete') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  NewRelic::Agent.record_custom_event('ClickhouseQuery', {
    sql: event.payload[:sql],
    duration_ms: event.duration,
    rows_read: event.payload[:rows_read],
  })
end

# Datadog integration
ActiveSupport::Notifications.subscribe('clickhouse_ruby.query.complete') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Datadog::Statsd.new.timing('clickhouse.query.duration', event.duration, tags: [
    "sql:#{event.payload[:sql].truncate(100)}",
  ])
end
```

---

## Best Practices

1. **Use environment variables** for sensitive data (passwords, hosts)
2. **Enable SSL** in production environments
3. **Set appropriate timeouts** based on your query patterns
4. **Tune pool size** based on concurrent request patterns
5. **Enable compression** for large payloads (>1KB)
6. **Configure retries** for transient failures
7. **Monitor pool health** regularly
8. **Use health check endpoints** for load balancers and monitoring systems
9. **Set up alerts** for pool exhaustion and connection failures
10. **Use separate clients** for read/write separation when needed

---

## See Also

- **[Configuration Guide](CONFIGURATION.md)** - Complete configuration reference
- **[Advanced Features](ADVANCED_FEATURES.md)** - Advanced usage patterns
- **[Performance Tuning](PERFORMANCE_TUNING.md)** - Performance optimization guide
- **[Usage Guide](USAGE.md)** - Common operations and error handling
