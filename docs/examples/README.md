# Examples

Real-world examples and patterns for ClickhouseRuby.

## Example Patterns

| Example | Description |
|---------|-------------|
| [Analytics Dashboard](#analytics-dashboard) | Time-based aggregations and charts |
| [ETL Pipeline](#etl-pipeline) | Extract, transform, load patterns |
| [Event Tracking](#event-tracking) | Real-time event collection |
| [Time Series](#time-series) | Time-series data analysis |

---

## Analytics Dashboard

Build analytics dashboards with time-based aggregations.

### Daily Event Counts

```ruby
class DashboardController < ApplicationController
  def daily_events
    events = Event.where(created_at: 7.days.ago..Time.now)
                  .group("toStartOfDay(created_at)")
                  .count

    render json: events
  end

  def hourly_events
    events = Event.where(created_at: 24.hours.ago..Time.now)
                  .group("toStartOfHour(created_at)")
                  .count

    render json: events
  end
end
```

### Approximate Queries with SAMPLE

For large datasets, use SAMPLE for faster results:

```ruby
def approximate_page_views
  PageView.sample(0.1)
          .where(timestamp: 1.hour.ago..Time.now)
          .group(:page)
          .count
end
```

### Optimized Query with PREWHERE

```ruby
def optimized_dashboard_data
  Event.prewhere(created_at: 1.day.ago..)
       .where(user_id: current_user.id)
       .group(:event_type)
       .count
end
```

---

## ETL Pipeline

Extract, transform, and load data from external sources.

### Basic ETL

```ruby
class EventETL
  def initialize
    @client = ClickhouseRuby.client
  end

  def run(source_data)
    transformed = source_data.map do |record|
      {
        id: SecureRandom.uuid,
        event_type: record[:type].downcase,
        user_id: record[:user],
        properties: record[:data].to_json,
        created_at: Time.now
      }
    end

    @client.insert('events', transformed)
  end
end

# Usage
etl = EventETL.new
etl.run(external_api_data)
```

### Chunked Processing

```ruby
def process_large_file(file_path)
  client = ClickhouseRuby.client

  File.foreach(file_path).each_slice(10_000) do |lines|
    records = lines.map { |line| parse_line(line) }
    client.insert('logs', records)
  end
end
```

### With Retry Logic

```ruby
def reliable_insert(table, records)
  retries = 0
  begin
    ClickhouseRuby.insert(table, records)
  rescue ClickhouseRuby::ConnectionError => e
    retries += 1
    if retries < 3
      sleep(2 ** retries)
      retry
    end
    raise
  end
end
```

---

## Event Tracking

Real-time event collection and analysis.

### Event Collector

```ruby
class EventCollector
  def track(event_type, user_id, properties = {})
    event = {
      id: SecureRandom.uuid,
      event_type: event_type,
      user_id: user_id,
      properties: properties.to_json,
      created_at: Time.now
    }

    ClickhouseRuby.insert('events', [event])
  end

  def track_batch(events)
    records = events.map do |e|
      {
        id: SecureRandom.uuid,
        event_type: e[:type],
        user_id: e[:user_id],
        properties: e[:properties].to_json,
        created_at: Time.now
      }
    end

    ClickhouseRuby.insert('events', records)
  end
end
```

### Streaming Live Data

```ruby
class ActivityController < ApplicationController
  include ActionController::Live

  def stream
    response.headers['Content-Type'] = 'text/event-stream'

    client = ClickhouseRuby.client
    client.each_row(
      "SELECT * FROM user_activity ORDER BY timestamp DESC LIMIT 100"
    ) do |activity|
      response.stream.write("data: #{activity.to_json}\n\n")
    end
  ensure
    response.stream.close
  end
end
```

---

## Time Series

Time-series data analysis patterns.

### Downsampling

```ruby
def get_metrics(interval:, start_time:, end_time:)
  client = ClickhouseRuby.client

  client.execute(<<~SQL)
    SELECT
      toStartOfInterval(timestamp, INTERVAL #{interval}) AS period,
      avg(value) AS avg_value,
      max(value) AS max_value,
      min(value) AS min_value
    FROM metrics
    WHERE timestamp BETWEEN '#{start_time}' AND '#{end_time}'
    GROUP BY period
    ORDER BY period
  SQL
end

# Usage
get_metrics(interval: '1 hour', start_time: 1.week.ago, end_time: Time.now)
```

### Moving Averages

```ruby
def moving_average(metric_name, window_size: 7)
  client = ClickhouseRuby.client

  client.execute(<<~SQL)
    SELECT
      date,
      value,
      avg(value) OVER (
        ORDER BY date
        ROWS BETWEEN #{window_size - 1} PRECEDING AND CURRENT ROW
      ) AS moving_avg
    FROM metrics
    WHERE metric = '#{metric_name}'
    ORDER BY date
  SQL
end
```

---

## Best Practices

### 1. Use Batch Inserts

```ruby
# Bad: Individual inserts
events.each { |e| client.insert('events', [e]) }

# Good: Batch insert
client.insert('events', events)
```

### 2. Stream Large Results

```ruby
# Bad: Load all into memory
results = client.execute('SELECT * FROM huge_table')

# Good: Stream processing
client.stream_execute('SELECT * FROM huge_table') do |row|
  process(row)
end
```

### 3. Use PREWHERE for Date Filters

```ruby
# Good: PREWHERE for date filters
Event.prewhere(date: Date.today).where(status: 'active')
```

### 4. Use SAMPLE for Approximate Results

```ruby
# Good: SAMPLE when exact count not needed
Event.sample(0.1).count * 10  # Estimate total
```

## See Also

- **[Guides](../guides/)** - How-to guides
- **[Reference](../reference/)** - API reference
