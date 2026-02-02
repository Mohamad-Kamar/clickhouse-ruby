# Feature: HTTP Compression

> **Status:** Not Started
> **Priority:** High (Batch 2)
> **Dependencies:** None

---

## Guardrails

- **Don't change:** Connection pool logic, error handling, existing request flow
- **Must keep:** Zero external dependencies (use Ruby Zlib only), backward compatibility
- **Definition of done:** All boxes checked + proof commands pass
- **Stop condition:** All checkboxes verified, integration tests pass

---

## Research Summary

### ClickHouse HTTP Compression Support

ClickHouse HTTP interface supports multiple compression algorithms:

| Algorithm | Request | Response | Ruby Support | Notes |
|-----------|---------|----------|--------------|-------|
| **gzip** | Yes | Yes | Built-in (Zlib) | Best compatibility |
| **deflate** | Yes | Yes | Built-in (Zlib) | RFC 1951 |
| **lz4** | Yes | Yes | External gem | Fast, moderate ratio |
| **zstd** | Yes | Yes | External gem | Best ratio |
| **br** (Brotli) | Yes | Yes | External gem | Web-optimized |

**For v0.2.0:** Implement gzip only (zero dependencies).

### HTTP Headers

**Request Compression (sending data to ClickHouse):**
```http
Content-Encoding: gzip
Content-Type: application/octet-stream
```

**Response Compression (receiving data from ClickHouse):**
```http
Accept-Encoding: gzip
```

**Query Parameters:**
```
?enable_http_compression=1
```

### Compression Flow

```
REQUEST:
Ruby Client → Zlib.gzip(body) → HTTP POST with Content-Encoding: gzip → ClickHouse

RESPONSE:
ClickHouse → gzip response → HTTP Response with Content-Encoding: gzip → Zlib.gunzip → Ruby Client
```

---

## Gotchas & Edge Cases

### 1. Enable Compression via Query Parameter
```ruby
# Just Accept-Encoding header is NOT enough
# Must also include enable_http_compression=1 in query string

# WRONG - No compression
uri.query = "query=SELECT..."
request['Accept-Encoding'] = 'gzip'

# CORRECT - Compression enabled
uri.query = "query=SELECT...&enable_http_compression=1"
request['Accept-Encoding'] = 'gzip'
```

### 2. Content-Type for Compressed Requests
```ruby
# When sending compressed body, use octet-stream
request['Content-Type'] = 'application/octet-stream'
request['Content-Encoding'] = 'gzip'
request.body = Zlib.gzip(json_body)
```

### 3. Net::HTTP Auto-Decompression
```ruby
# Net::HTTP automatically decompresses gzip responses
# UNLESS you set Accept-Encoding yourself

# Auto-decompression (response.body is already decompressed)
http.request(request)  # No Accept-Encoding header set

# Manual decompression required when header set explicitly
request['Accept-Encoding'] = 'gzip'
response = http.request(request)
body = Zlib.gunzip(response.body)  # Must decompress manually
```

**Important:** Since we need to set `Accept-Encoding` to ensure compression, we must handle decompression ourselves.

### 4. Streaming with Compression
```ruby
# For streaming responses, use Zlib::Inflate
inflater = Zlib::Inflate.new(16 + Zlib::MAX_WBITS)  # 16 for gzip header

response.read_body do |chunk|
  decompressed = inflater.inflate(chunk)
  # Process decompressed chunk
end

final = inflater.finish
inflater.close
```

### 5. Empty Response Handling
```ruby
# Empty responses may still have gzip headers
def decompress_response(body, content_encoding)
  return body if body.nil? || body.empty?
  return body unless content_encoding == 'gzip'

  Zlib.gunzip(body)
rescue Zlib::GzipFile::Error
  # Not actually gzipped despite header
  body
end
```

### 6. Compression Level Trade-offs
```ruby
# Level 1: Fastest, least compression (~60% ratio)
# Level 6: Default, balanced (~70% ratio)
# Level 9: Slowest, best compression (~75% ratio)

Zlib.gzip(body, level: Zlib::DEFAULT_COMPRESSION)  # Level 6
```

---

## Best Practices

### 1. Enable Compression by Default for Large Payloads
```ruby
# Only compress if body > threshold (e.g., 1KB)
COMPRESSION_THRESHOLD = 1024

def should_compress?(body)
  body.bytesize > COMPRESSION_THRESHOLD
end
```

### 2. Make Compression Configurable
```ruby
ClickhouseRuby.configure do |config|
  config.compression = 'gzip'  # or nil to disable
  config.compression_threshold = 1024
end
```

### 3. Handle Compression Errors Gracefully
```ruby
def safe_decompress(body, encoding)
  return body unless encoding == 'gzip'

  Zlib.gunzip(body)
rescue Zlib::Error => e
  # Log warning, return original body
  warn "Decompression failed: #{e.message}"
  body
end
```

### 4. Use Streaming Decompression for Large Responses
```ruby
# Don't load entire response into memory
# Use Zlib::Inflate for chunk-by-chunk decompression
```

---

## Implementation Details

### File Locations

| File | Purpose |
|------|---------|
| `lib/clickhouse_ruby/configuration.rb` | Add compression config |
| `lib/clickhouse_ruby/connection.rb` | Add compression logic |
| `spec/unit/clickhouse_ruby/configuration_spec.rb` | Config tests |
| `spec/unit/clickhouse_ruby/connection_spec.rb` | Connection tests |
| `spec/integration/compression_spec.rb` | Integration tests |

### Configuration Changes

```ruby
# lib/clickhouse_ruby/configuration.rb
class Configuration
  attr_accessor :compression
  attr_accessor :compression_threshold

  def initialize
    # ... existing ...
    @compression = nil  # 'gzip' to enable
    @compression_threshold = 1024  # bytes
  end

  def compression_enabled?
    @compression == 'gzip'
  end
end
```

### Connection Changes

```ruby
# lib/clickhouse_ruby/connection.rb
class Connection
  def initialize(compression: nil, compression_threshold: 1024, **options)
    # ... existing ...
    @compression = compression
    @compression_threshold = compression_threshold
  end

  def post(path, body = nil)
    request = Net::HTTP::Post.new(path)
    setup_headers(request)
    setup_body(request, body)

    response = @http.request(request)
    decompress_response(response)
  end

  private

  def setup_headers(request)
    request['Content-Type'] = 'application/json'

    if @compression == 'gzip'
      request['Accept-Encoding'] = 'gzip'
    end
  end

  def setup_body(request, body)
    return unless body

    if should_compress?(body)
      request['Content-Encoding'] = 'gzip'
      request['Content-Type'] = 'application/octet-stream'
      request.body = Zlib.gzip(body, level: Zlib::DEFAULT_COMPRESSION)
    else
      request.body = body
    end
  end

  def should_compress?(body)
    @compression == 'gzip' && body.bytesize > @compression_threshold
  end

  def decompress_response(response)
    return response unless response['Content-Encoding'] == 'gzip'

    # Create wrapper that decompresses body
    DecompressedResponse.new(response)
  end

  class DecompressedResponse
    def initialize(response)
      @response = response
      @decompressed_body = nil
    end

    def code
      @response.code
    end

    def [](header)
      @response[header]
    end

    def body
      @decompressed_body ||= Zlib.gunzip(@response.body)
    rescue Zlib::Error
      @response.body
    end
  end
end
```

### Query Parameter Addition

```ruby
# In client.rb build_query_params
def build_query_params(settings)
  params = {
    'database' => @config.database,
    # ... existing ...
  }

  if @config.compression_enabled?
    params['enable_http_compression'] = '1'
  end

  params.merge(settings.transform_values(&:to_s))
end
```

---

## Ralph Loop Checklist

- [ ] Configuration has `compression` option (nil, 'gzip')
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/configuration_spec.rb --example "compression option"`

- [ ] Configuration has `compression_threshold` option
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/configuration_spec.rb --example "compression_threshold"`

- [ ] Connection sends `Accept-Encoding: gzip` header when compression enabled
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/connection_spec.rb --example "Accept-Encoding"`

- [ ] Connection sends `Content-Encoding: gzip` for compressed request body
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/connection_spec.rb --example "Content-Encoding"`

- [ ] Connection compresses request body with Zlib when above threshold
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/connection_spec.rb --example "compress request"`

- [ ] Connection decompresses gzip responses automatically
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/connection_spec.rb --example "decompress response"`

- [ ] Query params include `enable_http_compression=1` when enabled
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/client_spec.rb --example "enable_http_compression"`

- [ ] Small requests below threshold are NOT compressed
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/connection_spec.rb --example "below threshold"`

- [ ] Integration test: compressed SELECT returns correct data
  **prove:** `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec spec/integration/compression_spec.rb --example "SELECT"`

- [ ] Integration test: compressed INSERT succeeds
  **prove:** `CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec spec/integration/compression_spec.rb --example "INSERT"`

- [ ] All unit tests pass
  **prove:** `bundle exec rake spec_unit`

- [ ] No lint errors
  **prove:** `bundle exec rake rubocop`

---

## Test Scenarios

```ruby
# spec/unit/clickhouse_ruby/connection_spec.rb
RSpec.describe ClickhouseRuby::Connection do
  describe 'compression' do
    let(:connection) do
      described_class.new(
        host: 'localhost',
        port: 8123,
        compression: 'gzip',
        compression_threshold: 100
      )
    end

    describe 'request compression' do
      let(:large_body) { 'x' * 200 }
      let(:small_body) { 'x' * 50 }

      it 'compresses large requests' do
        stub_request(:post, 'http://localhost:8123/')
          .with(headers: { 'Content-Encoding' => 'gzip' })
          .to_return(status: 200, body: '')

        connection.post('/', large_body)
        expect(WebMock).to have_requested(:post, 'http://localhost:8123/')
          .with(headers: { 'Content-Encoding' => 'gzip' })
      end

      it 'does not compress small requests' do
        stub_request(:post, 'http://localhost:8123/')
          .to_return(status: 200, body: '')

        connection.post('/', small_body)
        expect(WebMock).to have_requested(:post, 'http://localhost:8123/')
          .with { |req| req.headers['Content-Encoding'].nil? }
      end
    end

    describe 'response decompression' do
      it 'decompresses gzip responses' do
        compressed = Zlib.gzip('{"data": "test"}')
        stub_request(:post, 'http://localhost:8123/')
          .to_return(
            status: 200,
            body: compressed,
            headers: { 'Content-Encoding' => 'gzip' }
          )

        response = connection.post('/', 'query')
        expect(response.body).to eq('{"data": "test"}')
      end
    end
  end
end

# spec/integration/compression_spec.rb
RSpec.describe 'HTTP Compression', :integration do
  let(:client) do
    ClickhouseRuby::Client.new(
      ClickhouseRuby::Configuration.new.tap do |c|
        c.host = 'localhost'
        c.port = 8123
        c.compression = 'gzip'
      end
    )
  end

  it 'executes SELECT with compression' do
    result = client.execute('SELECT 1 AS num')
    expect(result.first['num']).to eq(1)
  end

  it 'executes INSERT with compressed body' do
    client.command('CREATE TABLE IF NOT EXISTS test_compress (id UInt64) ENGINE = Memory')

    # Large enough to trigger compression
    rows = (1..1000).map { |i| { id: i } }
    client.insert('test_compress', rows)

    result = client.execute('SELECT count() AS cnt FROM test_compress')
    expect(result.first['cnt']).to eq(1000)
  ensure
    client.command('DROP TABLE IF EXISTS test_compress')
  end
end
```

---

## Performance Expectations

| Scenario | Without Compression | With Compression | Savings |
|----------|--------------------|-----------------:|--------:|
| 1KB JSON response | 1KB | ~400B | 60% |
| 10KB JSON response | 10KB | ~3KB | 70% |
| 100KB JSON response | 100KB | ~25KB | 75% |
| 1MB bulk INSERT | 1MB | ~200KB | 80% |

**CPU Overhead:** ~5-15% for compression, ~10-20% for decompression (negligible for most use cases).

---

## References

- [ClickHouse HTTP Interface - Compression](https://clickhouse.com/docs/en/interfaces/http#compression)
- [Ruby Zlib Documentation](https://ruby-doc.org/stdlib/libdoc/zlib/rdoc/Zlib.html)
- [HTTP Compression Best Practices](https://developer.mozilla.org/en-US/docs/Web/HTTP/Compression)
