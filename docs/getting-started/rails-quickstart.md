# Rails Quickstart

Use ClickhouseRuby with Rails and ActiveRecord.

## Prerequisites

- Rails application
- ClickhouseRuby installed (`gem 'clickhouse-ruby'`)
- ClickHouse running

## Setup

### 1. Create Initializer

```ruby
# config/initializers/clickhouse_ruby.rb
require 'clickhouse_ruby/active_record'

ClickhouseRuby::ActiveRecord.establish_connection(
  host: ENV.fetch('CLICKHOUSE_HOST', 'localhost'),
  port: ENV.fetch('CLICKHOUSE_PORT', 8123),
  database: ENV.fetch('CLICKHOUSE_DATABASE', 'analytics')
)
```

### 2. Create a Model

```ruby
# app/models/event.rb
class Event < ClickhouseRuby::ActiveRecord::Base
  self.table_name = 'events'
end
```

### 3. Create the Table

You can create the table via migration generator (v0.3.0+) or manually.

**Using Migration Generator:**

```bash
rails generate clickhouse:migration CreateEvents \
  id:uuid \
  event_type:string \
  user_id:integer \
  created_at:datetime \
  --engine=MergeTree \
  --order-by="event_type,created_at"
```

This generates:

```ruby
# db/clickhouse_migrate/TIMESTAMP_create_events.rb
class CreateEvents < ClickhouseRuby::ActiveRecord::Migration
  def up
    execute <<~SQL
      CREATE TABLE events (
        id UUID,
        event_type String,
        user_id UInt64,
        created_at DateTime
      ) ENGINE = MergeTree()
      ORDER BY (event_type, created_at)
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS events"
  end
end
```

**Manual Creation:**

```ruby
# In Rails console
Event.connection.execute(<<~SQL)
  CREATE TABLE IF NOT EXISTS events (
    id UUID,
    event_type String,
    user_id UInt64,
    created_at DateTime
  ) ENGINE = MergeTree()
  ORDER BY (event_type, created_at)
SQL
```

## Basic Usage

### Query Data

```ruby
# Basic queries
Event.all
Event.where(event_type: 'page_view')
Event.where(user_id: 12345).limit(10)
Event.order(created_at: :desc).first

# Aggregations
Event.count
Event.group(:event_type).count
Event.where(created_at: 1.day.ago..Time.now).count
```

### Insert Data

```ruby
# Single record
Event.create(
  id: SecureRandom.uuid,
  event_type: 'page_view',
  user_id: 12345,
  created_at: Time.now
)

# Bulk insert (efficient)
Event.insert_all([
  { id: SecureRandom.uuid, event_type: 'click', user_id: 123, created_at: Time.now },
  { id: SecureRandom.uuid, event_type: 'view', user_id: 456, created_at: Time.now }
])
```

## ClickHouse Query Extensions

ClickhouseRuby adds ClickHouse-specific query methods:

### PREWHERE - Query Optimization

```ruby
# Filter before reading all columns (faster for large tables)
Event.prewhere(created_at: 1.day.ago..).where(event_type: 'click')
```

### FINAL - Deduplication

```ruby
# Get deduplicated results (for ReplacingMergeTree)
User.final.where(id: 123)
```

### SAMPLE - Approximate Queries

```ruby
# Query a sample for faster approximate results
Event.sample(0.1).count  # ~10% of data
```

### SETTINGS - Per-Query Configuration

```ruby
Event.settings(max_execution_time: 60).where(active: true)
```

## Example Controller

```ruby
# app/controllers/events_controller.rb
class EventsController < ApplicationController
  def index
    @events = Event.where(user_id: current_user.id)
                   .order(created_at: :desc)
                   .limit(100)
  end

  def stats
    @daily_counts = Event
      .where(created_at: 7.days.ago..Time.now)
      .group("toStartOfDay(created_at)")
      .count

    render json: @daily_counts
  end

  def create
    Event.insert_all(event_params.map do |e|
      e.merge(id: SecureRandom.uuid, created_at: Time.now)
    end)

    head :created
  end

  private

  def event_params
    params.require(:events).map do |e|
      e.permit(:event_type, :user_id, :properties)
    end
  end
end
```

## Configuration Tips

### Production Settings

```ruby
# config/initializers/clickhouse_ruby.rb
ClickhouseRuby::ActiveRecord.establish_connection(
  host: ENV['CLICKHOUSE_HOST'],
  port: ENV['CLICKHOUSE_PORT'],
  database: ENV['CLICKHOUSE_DATABASE'],
  username: ENV['CLICKHOUSE_USERNAME'],
  password: ENV['CLICKHOUSE_PASSWORD'],
  ssl: Rails.env.production?,
  pool_size: ENV.fetch('CLICKHOUSE_POOL_SIZE', 10).to_i,
  read_timeout: 60
)
```

### Multiple Databases

```ruby
# Analytics database
class AnalyticsRecord < ClickhouseRuby::ActiveRecord::Base
  self.abstract_class = true
  establish_connection(:clickhouse_analytics)
end

# Events inherit from Analytics
class Event < AnalyticsRecord
  self.table_name = 'events'
end
```

## Next Steps

- **[ActiveRecord Guide](../guides/activerecord.md)** - Complete ActiveRecord usage
- **[Migrations Guide](../guides/migrations.md)** - Migration patterns
- **[Production Guide](../guides/production.md)** - Production deployment
