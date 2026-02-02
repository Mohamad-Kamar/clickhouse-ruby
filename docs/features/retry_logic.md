# Feature: Connection Retry Logic

> **Status:** Implemented (v0.2.0)
> **Priority:** Core Feature (Released)
> **Dependencies:** None

---

## Guardrails

- **Don't change:** Existing error hierarchy, pool checkout/checkin behavior
- **Must keep:** Configurable retry params, exponential backoff with jitter, clear retriable/non-retriable distinction
- **Definition of done:** All boxes checked + proof commands pass
- **Stop condition:** All checkboxes verified, unit tests pass

---

## Research Summary

### Exponential Backoff Algorithm

Based on gRPC specification (industry standard for distributed systems):

```
Parameters:
- INITIAL_BACKOFF: Starting delay (default 1 second)
- MULTIPLIER: Growth factor (default 1.6)
- MAX_BACKOFF: Maximum delay cap (default 120 seconds)
- MAX_ATTEMPTS: Maximum retry attempts (default 3)

Algorithm:
delay = min(INITIAL_BACKOFF × (MULTIPLIER ^ attempt), MAX_BACKOFF)
```

### Jitter Strategies

Jitter prevents "thundering herd" when many clients retry simultaneously:

| Strategy | Formula | Best For |
|----------|---------|----------|
| **Full Jitter** | `random(0, delay)` | Many simultaneous clients |
| **Equal Jitter** | `delay/2 + random(0, delay/2)` | Balanced predictability (recommended) |
| **Decorrelated** | `random(initial, prev_delay × 3)` | Rapidly changing conditions |

**Recommendation:** Use Equal Jitter for predictable minimum wait with randomization.

### Retriable vs Non-Retriable Errors

| Error Type | Retriable | Reason |
|------------|-----------|--------|
| `ConnectionError` | Yes | Network transient |
| `ConnectionTimeout` | Yes | Server overloaded |
| `SSLError` | Maybe | Check specific error |
| `PoolTimeout` | Yes | Pool exhausted temporarily |
| HTTP 500-599 | Yes | Server errors |
| HTTP 429 | Yes | Rate limiting |
| `QueryError` | **No** | Syntax/logic error |
| `SyntaxError` | **No** | Bad SQL |
| HTTP 400-499 | **No** | Client errors |

---

## Gotchas & Edge Cases

### 1. POST Idempotency for INSERT
```ruby
# INSERT operations are NOT idempotent by default
# Retry can cause duplicate data!

# Solution: Use query_id for deduplication
client.insert('table', data, query_id: SecureRandom.uuid)
```

**Implementation:** Generate unique query_id on first attempt, reuse on retries.

### 2. Partial Success in Batch INSERT
```ruby
# Some rows may be inserted before error
# Retry could duplicate successful rows

# Solution: Use async_insert with deduplication
client.insert('table', data, settings: { async_insert: 1, insert_deduplicate: 1 })
```

### 3. Connection State After Error
```ruby
# After connection error, the connection may be in bad state
# Must checkin with error flag to remove from pool

pool.checkin(connection, error: true)  # Marks for removal
```

### 4. Timeout During Response
```ruby
# Request sent successfully but timeout during response
# Query may have executed on server!

# For SELECT: Safe to retry (idempotent)
# For INSERT: Risky - check for duplicates or use query_id
```

### 5. SSL Errors - Some Are Retriable
```ruby
# Retriable SSL errors:
# - OpenSSL::SSL::SSLError "read would block"
# - OpenSSL::SSL::SSLError "write would block"

# Non-retriable SSL errors:
# - Certificate verification failure
# - Protocol version mismatch
```

### 6. Retry Budget Exhaustion
```ruby
# Track retries across requests to prevent cascade
class RetryBudget
  def initialize(max_retries_per_second: 10)
    @budget = max_retries_per_second
    @last_refill = Time.now
  end

  def can_retry?
    refill_budget
    @budget > 0
  end

  def use_retry
    @budget -= 1
  end
end
```

---

## Best Practices

### 1. Always Use Jitter
```ruby
# Without jitter: All clients retry at same time
# With jitter: Retries spread out over time

def calculate_delay(attempt)
  base = @initial_backoff * (@multiplier ** attempt)
  capped = [base, @max_backoff].min
  # Equal jitter
  capped / 2.0 + rand * (capped / 2.0)
end
```

### 2. Log All Retries
```ruby
def execute_with_retry
  attempts = 0
  begin
    attempts += 1
    yield
  rescue RetriableError => e
    if attempts < @max_attempts
      delay = calculate_delay(attempts)
      logger.warn("Retry #{attempts}/#{@max_attempts} after #{delay}s: #{e.message}")
      sleep(delay)
      retry
    end
    raise
  end
end
```

### 3. Expose Retry Configuration
```ruby
ClickhouseRuby.configure do |config|
  config.max_retries = 3
  config.initial_backoff = 1.0
  config.max_backoff = 120.0
  config.backoff_multiplier = 1.6
  config.retry_jitter = :equal  # :full, :equal, :none
end
```

### 4. Circuit Breaker for Persistent Failures
```ruby
# After N consecutive failures, "open" the circuit
# Stop retrying for a cooldown period
# Gradually allow requests through ("half-open")
```

---

## Implementation Details

### File Locations

| File | Purpose |
|------|---------|
| `lib/clickhouse_ruby/retry_handler.rb` | Retry logic class |
| `lib/clickhouse_ruby/configuration.rb` | Retry config options |
| `lib/clickhouse_ruby/client.rb` | Integrate retry handler |
| `spec/unit/clickhouse_ruby/retry_handler_spec.rb` | Unit tests |

### RetryHandler Class

```ruby
# lib/clickhouse_ruby/retry_handler.rb
module ClickhouseRuby
  class RetryHandler
    RETRIABLE_ERRORS = [
      ConnectionError,
      ConnectionTimeout,
      ConnectionNotEstablished,
      PoolTimeout,
    ].freeze

    RETRIABLE_HTTP_CODES = %w[500 502 503 504 429].freeze

    def initialize(
      max_attempts: 3,
      initial_backoff: 1.0,
      max_backoff: 120.0,
      multiplier: 1.6,
      jitter: :equal
    )
      @max_attempts = max_attempts
      @initial_backoff = initial_backoff
      @max_backoff = max_backoff
      @multiplier = multiplier
      @jitter = jitter
    end

    def with_retry(idempotent: true, query_id: nil)
      attempts = 0
      generated_query_id = query_id || SecureRandom.uuid

      begin
        attempts += 1
        yield(generated_query_id)
      rescue *RETRIABLE_ERRORS => e
        handle_retry(attempts, e, idempotent)
        retry
      rescue QueryError => e
        # Check if HTTP code is retriable
        if retriable_http_error?(e)
          handle_retry(attempts, e, idempotent)
          retry
        end
        raise
      end
    end

    def retriable?(error)
      RETRIABLE_ERRORS.any? { |klass| error.is_a?(klass) } ||
        retriable_http_error?(error)
    end

    private

    def handle_retry(attempts, error, idempotent)
      if attempts >= @max_attempts
        raise error
      end

      unless idempotent
        warn "Retrying non-idempotent operation - possible duplicates"
      end

      delay = calculate_delay(attempts)
      sleep(delay)
    end

    def calculate_delay(attempt)
      base = @initial_backoff * (@multiplier ** (attempt - 1))
      capped = [base, @max_backoff].min

      case @jitter
      when :full
        rand * capped
      when :equal
        capped / 2.0 + rand * (capped / 2.0)
      when :none
        capped
      else
        capped / 2.0 + rand * (capped / 2.0)
      end
    end

    def retriable_http_error?(error)
      error.respond_to?(:http_status) &&
        RETRIABLE_HTTP_CODES.include?(error.http_status.to_s)
    end
  end
end
```

### Client Integration

```ruby
# lib/clickhouse_ruby/client.rb
class Client
  def initialize(config)
    # ... existing ...
    @retry_handler = RetryHandler.new(
      max_attempts: config.max_retries,
      initial_backoff: config.initial_backoff,
      max_backoff: config.max_backoff,
      multiplier: config.backoff_multiplier,
      jitter: config.retry_jitter
    )
  end

  def execute(sql, settings: {}, format: DEFAULT_FORMAT)
    @retry_handler.with_retry(idempotent: true) do
      execute_internal(sql, settings: settings, format: format)
    end
  end

  def insert(table, rows, columns: nil, settings: {})
    @retry_handler.with_retry(idempotent: false) do |query_id|
      settings_with_id = settings.merge(query_id: query_id)
      insert_internal(table, rows, columns: columns, settings: settings_with_id)
    end
  end

  private

  def execute_internal(sql, settings:, format:)
    # ... existing execute logic ...
  end

  def insert_internal(table, rows, columns:, settings:)
    # ... existing insert logic ...
  end
end
```

### Configuration Changes

```ruby
# lib/clickhouse_ruby/configuration.rb
class Configuration
  attr_accessor :max_retries
  attr_accessor :initial_backoff
  attr_accessor :max_backoff
  attr_accessor :backoff_multiplier
  attr_accessor :retry_jitter

  def initialize
    # ... existing ...
    @max_retries = 3
    @initial_backoff = 1.0
    @max_backoff = 120.0
    @backoff_multiplier = 1.6
    @retry_jitter = :equal
  end
end
```

---

## Ralph Loop Checklist

- [ ] `RetryHandler` class exists at `lib/clickhouse_ruby/retry_handler.rb`
  **prove:** `ruby -r./lib/clickhouse_ruby -e "ClickhouseRuby::RetryHandler"`

- [ ] Configuration has `max_retries` option
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/configuration_spec.rb --example "max_retries"`

- [ ] Configuration has `initial_backoff`, `max_backoff`, `backoff_multiplier` options
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/configuration_spec.rb --example "backoff"`

- [ ] Configuration has `retry_jitter` option (:full, :equal, :none)
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/configuration_spec.rb --example "jitter"`

- [ ] Implements exponential backoff: `delay = initial * (multiplier ^ attempt)`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/retry_handler_spec.rb --example "exponential"`

- [ ] Implements equal jitter: `delay/2 + random(0, delay/2)`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/retry_handler_spec.rb --example "equal jitter"`

- [ ] Retries on `ConnectionError`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/retry_handler_spec.rb --example "ConnectionError"`

- [ ] Retries on `ConnectionTimeout`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/retry_handler_spec.rb --example "ConnectionTimeout"`

- [ ] Retries on HTTP 500/502/503/504/429
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/retry_handler_spec.rb --example "HTTP 5xx"`

- [ ] Does NOT retry on `QueryError` (syntax errors)
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/retry_handler_spec.rb --example "QueryError"`

- [ ] Does NOT retry on `SyntaxError`
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/retry_handler_spec.rb --example "SyntaxError"`

- [ ] Generates unique query_id for INSERT retries
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/retry_handler_spec.rb --example "query_id"`

- [ ] `Client.execute` uses RetryHandler
  **prove:** `bundle exec rspec spec/unit/clickhouse_ruby/client_spec.rb --example "retry"`

- [ ] All unit tests pass
  **prove:** `bundle exec rake spec_unit`

- [ ] No lint errors
  **prove:** `bundle exec rake rubocop`

---

## Test Scenarios

```ruby
# spec/unit/clickhouse_ruby/retry_handler_spec.rb
RSpec.describe ClickhouseRuby::RetryHandler do
  subject(:handler) do
    described_class.new(
      max_attempts: 3,
      initial_backoff: 0.1,  # Fast for tests
      max_backoff: 1.0,
      multiplier: 2.0,
      jitter: :none  # Deterministic for tests
    )
  end

  describe '#with_retry' do
    context 'when operation succeeds' do
      it 'returns result without retry' do
        call_count = 0
        result = handler.with_retry { call_count += 1; 'success' }

        expect(result).to eq('success')
        expect(call_count).to eq(1)
      end
    end

    context 'when operation fails with retriable error' do
      it 'retries up to max_attempts' do
        call_count = 0
        expect {
          handler.with_retry do
            call_count += 1
            raise ClickhouseRuby::ConnectionError, 'network error'
          end
        }.to raise_error(ClickhouseRuby::ConnectionError)

        expect(call_count).to eq(3)
      end

      it 'succeeds after transient failure' do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          raise ClickhouseRuby::ConnectionError if call_count < 2
          'success'
        end

        expect(result).to eq('success')
        expect(call_count).to eq(2)
      end
    end

    context 'when operation fails with non-retriable error' do
      it 'does not retry' do
        call_count = 0
        expect {
          handler.with_retry do
            call_count += 1
            raise ClickhouseRuby::SyntaxError, 'bad SQL'
          end
        }.to raise_error(ClickhouseRuby::SyntaxError)

        expect(call_count).to eq(1)
      end
    end
  end

  describe '#calculate_delay' do
    it 'uses exponential backoff' do
      delays = (1..3).map { |n| handler.send(:calculate_delay, n) }

      expect(delays[0]).to eq(0.1)   # 0.1 * 2^0
      expect(delays[1]).to eq(0.2)   # 0.1 * 2^1
      expect(delays[2]).to eq(0.4)   # 0.1 * 2^2
    end

    it 'caps at max_backoff' do
      delay = handler.send(:calculate_delay, 100)
      expect(delay).to eq(1.0)  # max_backoff
    end
  end

  describe 'jitter strategies' do
    it 'applies equal jitter' do
      handler = described_class.new(jitter: :equal, initial_backoff: 1.0)
      delays = 100.times.map { handler.send(:calculate_delay, 1) }

      # Equal jitter: delay/2 + random(0, delay/2)
      # So delays should be between 0.5 and 1.0
      expect(delays.min).to be >= 0.5
      expect(delays.max).to be <= 1.0
      expect(delays.uniq.size).to be > 1  # Some variance
    end
  end
end
```

---

## Backoff Timeline Example

With defaults (initial=1s, multiplier=1.6, max=120s):

| Attempt | Base Delay | With Jitter (Equal) |
|---------|------------|---------------------|
| 1 | 1.0s | 0.5s - 1.0s |
| 2 | 1.6s | 0.8s - 1.6s |
| 3 | 2.56s | 1.28s - 2.56s |
| 4 | 4.1s | 2.05s - 4.1s |
| 5 | 6.55s | 3.28s - 6.55s |
| ... | ... | ... |
| 15 | 120s (capped) | 60s - 120s |

---

## References

- [gRPC Retry Design](https://github.com/grpc/proposal/blob/master/A6-client-retries.md)
- [AWS Exponential Backoff](https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/)
- [Google Cloud Retry Best Practices](https://cloud.google.com/storage/docs/retry-strategy)
