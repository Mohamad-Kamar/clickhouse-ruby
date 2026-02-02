# Feature: Result Streaming

> **Status:** Implemented (v0.2.0)
> **Priority:** Core Feature (Released)
> **Dependencies:** HTTP Compression (optional, but complementary)

---

## Guardrails

- **Don't change:** Existing `Result` class, `client.execute` behavior
- **Must keep:** Memory-efficient (constant memory for any result size), Enumerable interface, zero external dependencies
- **Definition of done:** All boxes checked + proof commands pass
- **Stop condition:** All checkboxes verified, integration tests pass

---

## Research Summary

### Why Streaming?

| Scenario | Without Streaming | With Streaming |
|----------|-------------------|----------------|
| 1M rows query | ~2GB RAM | ~50KB RAM |
| First row latency | Wait for all | Immediate |
| Cancel mid-query | Lose all data | Keep processed |

### ClickHouse Streaming Protocol

ClickHouse HTTP interface supports streaming via:

1. **Chunked Transfer Encoding:** `Transfer-Encoding: chunked`
2. **JSONEachRow Format:** One JSON object per line (natural streaming boundary)
3. **Progress Headers:** `X-ClickHouse-Progress` for real-time metrics

### Net::HTTP Streaming

```ruby
# Block-based streaming - body NOT loaded into memory
http.request(request) do |response|
  response.read_body do |chunk|
    # Process each chunk as it arrives
  end
end
```

### JSONEachRow Format

```json
{"id":1,"name":"Alice"}
{"id":2,"name":"Bob"}
{"id":3,"name":"Charlie"}
```

Each line is a complete JSON object - perfect for line-by-line streaming.

---

## Gotchas & Edge Cases

### 1. Net::HTTP Header Access Timing
```ruby
# Headers are available BEFORE body streaming starts
http.request(request) do |response|
  # Check status first!
  raise Error unless response.code == '200'

  # Then stream body
  response.read_body { |chunk| ... }
end
```

### 2. Incomplete Line Buffering
```ruby
# Chunks may split in middle of a line
buffer = ""
response.read_body do |chunk|
  buffer += chunk

  # Process complete lines only
  while buffer.include?("\n")
    line, buffer = buffer.split("\n", 2)
    yield JSON.parse(line)
  end
end

# Don't forget last line (may not end with \n)
yield JSON.parse(buffer) if buffer.strip.length > 0
```

### 3. Compression + Streaming
```ruby
# Must decompress chunks before parsing
inflater = Zlib::Inflate.new(16 + Zlib::MAX_WBITS)

response.read_body do |chunk|
  decompressed = inflater.inflate(chunk)
  # Now parse decompressed data
end

inflater.finish
inflater.close
```

### 4. Error in Middle of Stream
```ruby
# ClickHouse may return error after sending partial data
# Error appears as JSON in stream:
# {"exception": {"code": 60, "name": "UNKNOWN_TABLE", ...}}

# Must detect and raise
def parse_line(line)
  data = JSON.parse(line)
  if data['exception']
    raise QueryError.from_response(data)
  end
  data
end
```

### 5. Empty Result Set
```ruby
# Empty result = empty body, no lines
# Must handle gracefully
def each_row
  return enum_for(__method__) unless block_given?

  has_rows = false
  stream_response do |row|
    has_rows = true
    yield row
  end

  # Empty result is valid, not an error
end
```

### 6. Connection Reuse with Streaming
```ruby
# Connection is held during entire stream
# Long-running streams block pool

# Solution: Use dedicated connection for streaming
def stream_execute(sql)
  # Don't use pool - create dedicated connection
  connection = Connection.new(@config.to_connection_options)
  begin
    yield StreamingResult.new(connection, sql)
  ensure
    connection.close
  end
end
```

---

## Best Practices

### 1. Use Lazy Enumerator
```ruby
# Return Enumerator for chainable operations
def each_row(sql)
  return enum_for(__method__, sql) unless block_given?
  # ...
end

# Usage - memory efficient
client.each_row('SELECT * FROM huge')
  .lazy
  .select { |row| row['active'] }
  .take(100)
  .each { |row| process(row) }
```

### 2. Track Progress
```ruby
# Parse X-ClickHouse-Progress header
# {"read_rows":"1000","read_bytes":"50000","elapsed_ns":"1000000"}

def on_progress(&block)
  @progress_callback = block
end

# In streaming loop:
if progress = response['X-ClickHouse-Progress']
  @progress_callback&.call(JSON.parse(progress))
end
```

### 3. Support Early Termination
```ruby
# Allow caller to stop streaming
def each_row(sql)
  return enum_for(__method__, sql) unless block_given?

  stream_response(sql) do |row|
    result = yield row
    break if result == :stop  # Early termination
  end
end
```

### 4. Batch Processing Option
```ruby
# Process in batches for efficiency
def each_batch(sql, size: 1000)
  batch = []
  each_row(sql) do |row|
    batch << row
    if batch.size >= size
      yield batch
      batch = []
    end
  end
  yield batch if batch.any?
end
```

---

## Implementation Details

### File Locations

| File | Purpose |
|------|---------|
| `lib/clickhouse_ruby/streaming_result.rb` | Streaming result class |
| `lib/clickhouse_ruby/client.rb` | Add stream_execute method |
| `spec/unit/clickhouse_ruby/streaming_result_spec.rb` | Unit tests |
| `spec/integration/streaming_spec.rb` | Integration tests |

### StreamingResult Class

```ruby
# lib/clickhouse_ruby/streaming_result.rb
module ClickhouseRuby
  class StreamingResult
    include Enumerable

    def initialize(connection, sql, format: 'JSONEachRow', compression: nil)
      @connection = connection
      @sql = sql
      @format = format
      @compression = compression
      @progress_callback = nil
    end

    def on_progress(&block)
      @progress_callback = block
      self
    end

    def each
      return enum_for(__method__) unless block_given?

      stream_query do |row|
        yield row
      end
    end

    def each_batch(size: 1000)
      return enum_for(__method__, size: size) unless block_given?

      batch = []
      each do |row|
        batch << row
        if batch.size >= size
          yield batch
          batch = []
        end
      end
      yield batch if batch.any?
    end

    private

    def stream_query
      uri = build_uri
      request = build_request(uri)

      Net::HTTP.start(uri.host, uri.port, use_ssl: @connection.use_ssl?) do |http|
        http.request(request) do |response|
          check_response_status(response)
          handle_progress(response)

          parse_streaming_body(response) do |row|
            yield row
          end
        end
      end
    end

    def build_uri
      uri = URI("http://#{@connection.host}:#{@connection.port}/")
      params = {
        'database' => @connection.database,
        'query' => "#{@sql} FORMAT #{@format}"
      }
      params['enable_http_compression'] = '1' if @compression
      uri.query = URI.encode_www_form(params)
      uri
    end

    def build_request(uri)
      request = Net::HTTP::Get.new(uri)
      request['Accept-Encoding'] = 'gzip' if @compression
      request
    end

    def check_response_status(response)
      return if response.code == '200'

      # Read body for error message
      body = response.body
      raise_clickhouse_error(response, body)
    end

    def handle_progress(response)
      return unless @progress_callback

      if progress = response['X-ClickHouse-Progress']
        @progress_callback.call(JSON.parse(progress))
      end
    end

    def parse_streaming_body(response)
      decompressor = create_decompressor(response)
      buffer = ""

      response.read_body do |chunk|
        data = decompressor ? decompressor.inflate(chunk) : chunk
        buffer += data

        while buffer.include?("\n")
          line, buffer = buffer.split("\n", 2)
          next if line.empty?

          row = parse_row(line)
          yield row if row
        end
      end

      # Finalize decompression
      if decompressor
        buffer += decompressor.finish
        decompressor.close
      end

      # Process remaining buffer
      if buffer.strip.length > 0
        row = parse_row(buffer)
        yield row if row
      end
    end

    def create_decompressor(response)
      case response['Content-Encoding']
      when 'gzip'
        Zlib::Inflate.new(16 + Zlib::MAX_WBITS)
      else
        nil
      end
    end

    def parse_row(line)
      data = JSON.parse(line)

      # Check for error in stream
      if data['exception']
        raise QueryError.new(
          data['exception']['message'],
          code: data['exception']['code']
        )
      end

      data
    end
  end
end
```

### Client Integration

```ruby
# lib/clickhouse_ruby/client.rb
class Client
  # Existing execute returns Result (all in memory)
  def execute(sql, settings: {}, format: DEFAULT_FORMAT)
    # ... existing ...
  end

  # New streaming method
  def stream_execute(sql, settings: {})
    # Create dedicated connection (not from pool)
    connection = Connection.new(@config.to_connection_options)

    StreamingResult.new(
      connection,
      sql,
      compression: @config.compression
    )
  end

  # Convenience method for iteration
  def each_row(sql, settings: {}, &block)
    stream_execute(sql, settings: settings).each(&block)
  end

  # Batch iteration
  def each_batch(sql, batch_size: 1000, settings: {}, &block)
    stream_execute(sql, settings: settings).each_batch(size: batch_size, &block)
  end
end
```

---

## Ralph Loop Checklist

- [ ] `StreamingResult` class exists at `lib/clickhouse_ruby/streaming_result.rb`
  **prove:** `ruby -r./lib/clickhouse_ruby -e "ClickhouseRuby::StreamingResult"`

- [ ] Implements `Enumerable` interface
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/streaming_result_spec.rb --example "Enumerable"`

- [ ] Uses JSONEachRow format for line-by-line parsing
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/streaming_result_spec.rb --example "JSONEachRow"`

- [ ] Client has `stream_execute(sql)` method
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/client_spec.rb --example "stream_execute"`

- [ ] Client has `each_row(sql)` convenience method
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/client_spec.rb --example "each_row"`

- [ ] Yields rows one at a time via block
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/streaming_result_spec.rb --example "yields rows"`

- [ ] Returns lazy Enumerator when no block given
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/streaming_result_spec.rb --example "Enumerator"`

- [ ] Handles incomplete line buffering correctly
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/streaming_result_spec.rb --example "buffer"`

- [ ] Supports `each_batch(size:)` for batch processing
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/streaming_result_spec.rb --example "each_batch"`

- [ ] Decompresses gzip responses during streaming
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/streaming_result_spec.rb --example "gzip"`

- [ ] Integration test: stream 10K rows with constant memory
  **prove:** `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec spec/integration/streaming_spec.rb --example "memory"`

- [ ] All unit tests pass
  **prove:** `bundle exec rake spec_unit`

- [ ] No lint errors
  **prove:** `bundle exec rake rubocop`

---

## Test Scenarios

```ruby
# spec/unit/clickhouse_ruby/streaming_result_spec.rb
RSpec.describe ClickhouseRuby::StreamingResult do
  let(:connection) { instance_double(ClickhouseRuby::Connection) }

  describe '#each' do
    it 'yields rows one at a time' do
      # Simulate streaming response
      chunks = [
        '{"id":1,"name":"Alice"}\n',
        '{"id":2,"name":"Bob"}\n{"id":3',
        ',"name":"Charlie"}\n'
      ]

      rows = []
      result = described_class.new(connection, 'SELECT *')
      allow(result).to receive(:stream_query).and_yield(
        {'id' => 1, 'name' => 'Alice'}
      ).and_yield(
        {'id' => 2, 'name' => 'Bob'}
      ).and_yield(
        {'id' => 3, 'name' => 'Charlie'}
      )

      result.each { |row| rows << row }

      expect(rows.size).to eq(3)
      expect(rows[0]['name']).to eq('Alice')
    end

    it 'returns Enumerator without block' do
      result = described_class.new(connection, 'SELECT *')
      expect(result.each).to be_a(Enumerator)
    end
  end

  describe '#each_batch' do
    it 'yields batches of specified size' do
      result = described_class.new(connection, 'SELECT *')
      allow(result).to receive(:each).and_yield(
        {'id' => 1}
      ).and_yield(
        {'id' => 2}
      ).and_yield(
        {'id' => 3}
      )

      batches = []
      result.each_batch(size: 2) { |batch| batches << batch }

      expect(batches.size).to eq(2)
      expect(batches[0].size).to eq(2)
      expect(batches[1].size).to eq(1)
    end
  end
end

# spec/integration/streaming_spec.rb
RSpec.describe 'Result Streaming', :integration do
  let(:client) { ClickhouseHelper.client }

  before do
    client.command(<<~SQL)
      CREATE TABLE IF NOT EXISTS stream_test (
        id UInt64,
        data String
      ) ENGINE = MergeTree() ORDER BY id
    SQL

    # Insert test data
    rows = (1..1000).map { |i| { id: i, data: "row_#{i}" } }
    client.insert('stream_test', rows)
  end

  after do
    client.command('DROP TABLE IF EXISTS stream_test')
  end

  it 'streams rows without loading all into memory' do
    count = 0
    client.each_row('SELECT * FROM stream_test') do |row|
      count += 1
      break if count >= 100  # Early termination
    end

    expect(count).to eq(100)
  end

  it 'supports lazy enumeration' do
    result = client.stream_execute('SELECT * FROM stream_test')
      .lazy
      .select { |row| row['id'].even? }
      .take(10)
      .to_a

    expect(result.size).to eq(10)
    expect(result.all? { |row| row['id'].even? }).to be true
  end

  it 'processes in batches' do
    batch_count = 0
    client.each_batch('SELECT * FROM stream_test', batch_size: 100) do |batch|
      batch_count += 1
      expect(batch.size).to be <= 100
    end

    expect(batch_count).to eq(10)  # 1000 rows / 100 per batch
  end
end
```

---

## Memory Profile Example

```ruby
# Without streaming
result = client.execute('SELECT * FROM huge_table')  # Loads all into memory
result.each { |row| process(row) }

# Memory: O(n) where n = row count

# With streaming
client.each_row('SELECT * FROM huge_table') do |row|
  process(row)
end

# Memory: O(1) constant regardless of row count
```

---

## References

- [ClickHouse HTTP Interface](https://clickhouse.com/docs/en/interfaces/http)
- [Ruby Net::HTTP Streaming](https://ruby-doc.org/stdlib/libdoc/net/http/rdoc/Net/HTTP.html)
- [Ruby Enumerator Documentation](https://ruby-doc.org/core/Enumerator.html)
