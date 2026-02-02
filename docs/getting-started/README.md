# Getting Started

Welcome to ClickhouseRuby! These tutorials will get you up and running quickly.

## Tutorials

| Tutorial | Description | Time |
|----------|-------------|------|
| [Installation](installation.md) | Install the gem and set up ClickHouse | 5 min |
| [First Query](first-query.md) | Create a table, insert data, run queries | 10 min |
| [Rails Quickstart](rails-quickstart.md) | Use ClickhouseRuby with Rails/ActiveRecord | 10 min |

## Quick Path

**Just want to try it out?** Follow these steps:

```bash
# 1. Install
gem install clickhouse-ruby

# 2. Start ClickHouse (if needed)
docker run -d -p 8123:8123 clickhouse/clickhouse-server

# 3. Try it
irb -r clickhouse_ruby
```

```ruby
# In IRB
client = ClickhouseRuby::Client.new(host: 'localhost')
client.execute('SELECT 1 + 1 AS result')
# => [{"result" => 2}]
```

## Prerequisites

- Ruby >= 2.6.0
- ClickHouse >= 20.x (tested with 24.x)
- Docker (optional, for local ClickHouse)

## Next Steps

After completing the tutorials:

- **[Configuration Guide](../guides/configuration.md)** - All configuration options
- **[Querying Guide](../guides/querying.md)** - Advanced query patterns
- **[Production Guide](../guides/production.md)** - Deploy to production
