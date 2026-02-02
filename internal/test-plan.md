# Test Plan: ClickhouseRuby

## Overview

This document defines the TDD approach, test infrastructure, and test categories for the Chruby gem.

## Test Infrastructure

### Testing Framework

**RSpec** - Primary testing framework

```ruby
# Gemfile (development/test)
group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'rspec-its'
  gem 'rspec-collection_matchers'
end
```

### WebMock for HTTP Mocking

Mock HTTP interactions for reliable unit tests:

```ruby
# Gemfile
group :test do
  gem 'webmock', '~> 3.18'
end

# spec/spec_helper.rb
require 'webmock/rspec'

# Allow real connections for integration tests
WebMock.disable_net_connect!(allow_localhost: true)
```

### Docker-based ClickHouse

```yaml
# docker-compose.yml
version: '3.8'
services:
  clickhouse:
    image: clickhouse/clickhouse-server:24.1
    ports:
      - "8123:8123"    # HTTP
      - "9000:9000"    # Native (future)
    volumes:
      - ./spec/fixtures/init.sql:/docker-entrypoint-initdb.d/init.sql
    environment:
      CLICKHOUSE_DB: clickhouse_ruby_test
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ""
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8123/ping"]
      interval: 5s
      timeout: 3s
      retries: 10
```

### CI/CD Pipeline

```yaml
# .github/workflows/test.yml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      clickhouse:
        image: clickhouse/clickhouse-server:24.1
        ports:
          - 8123:8123
        options: >-
          --health-cmd "wget --spider -q http://localhost:8123/ping"
          --health-interval 5s
          --health-timeout 3s
          --health-retries 10

    strategy:
      matrix:
        ruby: ['3.1', '3.2', '3.3']
        rails: ['7.1', '7.2', '8.0']

    env:
      CLICKHOUSE_HOST: localhost
      CLICKHOUSE_PORT: 8123
      CLICKHOUSE_DATABASE: clickhouse_ruby_test

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true

      - name: Wait for ClickHouse
        run: |
          timeout 60 bash -c 'until curl -s http://localhost:8123/ping; do sleep 1; done'

      - name: Create test database
        run: |
          curl "http://localhost:8123/" --data "CREATE DATABASE IF NOT EXISTS clickhouse_ruby_test"

      - name: Run unit tests
        run: bundle exec rspec spec/unit

      - name: Run integration tests
        run: bundle exec rspec spec/integration

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: coverage/coverage.xml
```

### Code Quality Tools

```ruby
# Gemfile
group :development do
  gem 'rubocop', '~> 1.50'
  gem 'rubocop-rspec', '~> 2.20'
  gem 'rubocop-performance', '~> 1.17'
  gem 'rubocop-rails', '~> 2.19'
end

group :test do
  gem 'simplecov', '~> 0.22'
  gem 'simplecov-cobertura'  # For CI coverage reports
end
```

```yaml
# .rubocop.yml
require:
  - rubocop-rspec
  - rubocop-performance
  - rubocop-rails

AllCops:
  TargetRubyVersion: 3.1
  NewCops: enable
  Exclude:
    - 'vendor/**/*'
    - 'spec/fixtures/**/*'

Metrics/BlockLength:
  Exclude:
    - 'spec/**/*'
    - '*.gemspec'

RSpec/ExampleLength:
  Max: 20

RSpec/MultipleExpectations:
  Max: 5
```

## Test Categories

### 1. Unit Tests (`spec/unit/`)

Test individual components in isolation with mocked dependencies.

**Coverage Target:** 95%

```
spec/unit/
├── clickhouse_ruby/
│   ├── configuration_spec.rb
│   ├── client_spec.rb
│   ├── connection_spec.rb
│   ├── connection_pool_spec.rb
│   ├── result_spec.rb
│   ├── types/
│   │   ├── parser_spec.rb
│   │   ├── registry_spec.rb
│   │   ├── integer_spec.rb
│   │   ├── string_spec.rb
│   │   ├── datetime_spec.rb
│   │   ├── array_spec.rb
│   │   ├── map_spec.rb
│   │   ├── tuple_spec.rb
│   │   ├── nullable_spec.rb
│   │   └── low_cardinality_spec.rb
│   ├── query/
│   │   ├── builder_spec.rb
│   │   ├── select_spec.rb
│   │   └── insert_spec.rb
│   └── errors_spec.rb
└── active_record/
    ├── arel_visitor_spec.rb
    ├── schema_statements_spec.rb
    └── table_definition_spec.rb
```

**Example Unit Test:**

```ruby
# spec/unit/clickhouse_ruby/types/parser_spec.rb
RSpec.describe Chruby::Types::Parser do
  subject(:parser) { described_class.new }

  describe '#parse' do
    context 'with simple types' do
      it 'parses String' do
        result = parser.parse('String')
        expect(result).to eq({ type: 'String' })
      end

      it 'parses UInt64' do
        result = parser.parse('UInt64')
        expect(result).to eq({ type: 'UInt64' })
      end
    end

    context 'with parameterized types' do
      it 'parses Nullable(String)' do
        result = parser.parse('Nullable(String)')
        expect(result).to eq({
          type: 'Nullable',
          args: [{ type: 'String' }]
        })
      end

      it 'parses Array(UInt64)' do
        result = parser.parse('Array(UInt64)')
        expect(result).to eq({
          type: 'Array',
          args: [{ type: 'UInt64' }]
        })
      end

      it 'parses Map(String, UInt64)' do
        result = parser.parse('Map(String, UInt64)')
        expect(result).to eq({
          type: 'Map',
          args: [{ type: 'String' }, { type: 'UInt64' }]
        })
      end
    end

    context 'with nested types' do
      it 'parses Array(Tuple(String, UInt64))' do
        result = parser.parse('Array(Tuple(String, UInt64))')
        expect(result).to eq({
          type: 'Array',
          args: [{
            type: 'Tuple',
            args: [{ type: 'String' }, { type: 'UInt64' }]
          }]
        })
      end

      it 'parses deeply nested types' do
        result = parser.parse('Map(String, Array(Nullable(UInt64)))')
        expect(result).to eq({
          type: 'Map',
          args: [
            { type: 'String' },
            {
              type: 'Array',
              args: [{
                type: 'Nullable',
                args: [{ type: 'UInt64' }]
              }]
            }
          ]
        })
      end
    end

    context 'with LowCardinality' do
      it 'parses LowCardinality(String)' do
        result = parser.parse('LowCardinality(String)')
        expect(result).to eq({
          type: 'LowCardinality',
          args: [{ type: 'String' }]
        })
      end
    end
  end
end
```

### 2. Integration Tests (`spec/integration/`)

Test real interactions with ClickHouse server.

**Coverage Target:** 80%

```
spec/integration/
├── connection_spec.rb
├── query_execution_spec.rb
├── bulk_insert_spec.rb
├── type_coercion_spec.rb
├── error_handling_spec.rb
├── active_record/
│   ├── adapter_spec.rb
│   ├── migrations_spec.rb
│   ├── crud_spec.rb
│   ├── queries_spec.rb
│   └── prewhere_spec.rb
└── clickhouse_features/
    ├── merge_tree_spec.rb
    ├── materialized_views_spec.rb
    ├── ttl_spec.rb
    └── mutations_spec.rb
```

**Example Integration Test:**

```ruby
# spec/integration/error_handling_spec.rb
RSpec.describe 'Error Handling', :integration do
  let(:client) { Chruby::Client.new(test_config) }

  describe 'query errors' do
    it 'raises StatementInvalid for syntax errors' do
      expect {
        client.execute('SELEC * FROM nonexistent')
      }.to raise_error(Chruby::StatementInvalid) do |error|
        expect(error.message).to include('Syntax error')
        expect(error.sql).to eq('SELEC * FROM nonexistent')
      end
    end

    it 'raises QueryError with ClickHouse error code' do
      expect {
        client.execute('SELECT * FROM nonexistent_table_xyz')
      }.to raise_error(Chruby::QueryError) do |error|
        expect(error.code).to eq(60)  # UNKNOWN_TABLE
        expect(error.http_status).to eq('404')
      end
    end

    it 'does NOT silently fail on DELETE errors' do
      # This is the critical fix for issue #230
      client.execute('CREATE TABLE test_delete (id UInt64) ENGINE = MergeTree ORDER BY id')
      client.execute('INSERT INTO test_delete VALUES (1), (2), (3)')

      expect {
        # Attempt delete with nondeterministic subquery (should fail)
        client.execute('ALTER TABLE test_delete DELETE WHERE id IN (SELECT id FROM test_delete WHERE rand() > 0.5)')
      }.to raise_error(Chruby::QueryError)

      # Verify data was NOT deleted
      result = client.execute('SELECT count() FROM test_delete')
      expect(result.first['count()']).to eq(3)
    ensure
      client.execute('DROP TABLE IF EXISTS test_delete')
    end
  end

  describe 'connection errors' do
    it 'raises ConnectionNotEstablished for refused connections' do
      bad_client = Chruby::Client.new(host: 'localhost', port: 59999)

      expect {
        bad_client.execute('SELECT 1')
      }.to raise_error(Chruby::ConnectionNotEstablished)
    end

    it 'raises ConnectionTimeout when query exceeds timeout' do
      slow_client = Chruby::Client.new(test_config.merge(read_timeout: 0.001))

      expect {
        slow_client.execute('SELECT sleep(1)')
      }.to raise_error(Chruby::ConnectionTimeout)
    end
  end
end
```

### 3. End-to-End Tests (`spec/e2e/`)

Test complete workflows with Rails integration.

**Coverage Target:** 70%

```
spec/e2e/
├── rails_app/               # Minimal Rails app for testing
│   ├── config/
│   ├── app/
│   │   └── models/
│   │       ├── event.rb
│   │       └── user_stat.rb
│   └── db/
│       └── migrate/
├── model_lifecycle_spec.rb
├── migration_workflow_spec.rb
└── query_interface_spec.rb
```

**Example E2E Test:**

```ruby
# spec/e2e/model_lifecycle_spec.rb
RSpec.describe 'Model Lifecycle', :e2e do
  before(:all) do
    # Create test table
    Event.connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS events (
        id UInt64,
        event_type String,
        user_id UInt64,
        data String,
        created_at DateTime
      ) ENGINE = MergeTree
      ORDER BY (created_at, id)
    SQL
  end

  after(:all) do
    Event.connection.execute('DROP TABLE IF EXISTS events')
  end

  describe 'querying' do
    before do
      Event.insert_all([
        { id: 1, event_type: 'click', user_id: 100, data: '{}', created_at: Time.now },
        { id: 2, event_type: 'view', user_id: 100, data: '{}', created_at: Time.now },
        { id: 3, event_type: 'click', user_id: 200, data: '{}', created_at: Time.now }
      ])
    end

    after do
      Event.delete_all
    end

    it 'supports basic where clauses' do
      events = Event.where(user_id: 100)
      expect(events.count).to eq(2)
    end

    it 'supports PREWHERE for optimization' do
      # PREWHERE should be in the generated SQL
      events = Event.prewhere(event_type: 'click').where(user_id: 100)
      expect(events.to_sql).to include('PREWHERE')
      expect(events.count).to eq(1)
    end

    it 'supports aggregations' do
      result = Event.group(:event_type).count
      expect(result).to eq({ 'click' => 2, 'view' => 1 })
    end
  end

  describe 'bulk inserts' do
    it 'inserts many rows efficiently' do
      records = 10_000.times.map do |i|
        { id: i, event_type: 'test', user_id: i % 100, data: '{}', created_at: Time.now }
      end

      # Should complete in reasonable time and not fail
      expect {
        Event.insert_all(records)
      }.not_to raise_error

      expect(Event.count).to eq(10_000)
    end
  end
end
```

## Test Database Seeding Strategy

### Test Helper

```ruby
# spec/support/clickhouse_helper.rb
module ClickhouseHelper
  def self.setup_test_database
    client = Chruby::Client.new(
      host: ENV.fetch('CLICKHOUSE_HOST', 'localhost'),
      port: ENV.fetch('CLICKHOUSE_PORT', 8123).to_i,
      database: 'default'
    )

    database = ENV.fetch('CLICKHOUSE_DATABASE', 'clickhouse_ruby_test')

    client.execute("CREATE DATABASE IF NOT EXISTS #{database}")
    client.execute("USE #{database}")
  end

  def self.teardown_test_database
    client = Chruby::Client.new(
      host: ENV.fetch('CLICKHOUSE_HOST', 'localhost'),
      port: ENV.fetch('CLICKHOUSE_PORT', 8123).to_i,
      database: 'default'
    )

    database = ENV.fetch('CLICKHOUSE_DATABASE', 'clickhouse_ruby_test')
    client.execute("DROP DATABASE IF EXISTS #{database}")
  end

  def self.truncate_tables
    client = test_client
    tables = client.execute("SHOW TABLES").map { |row| row['name'] }

    tables.each do |table|
      client.execute("TRUNCATE TABLE #{table}")
    end
  end

  def self.test_client
    @test_client ||= Chruby::Client.new(test_config)
  end

  def self.test_config
    {
      host: ENV.fetch('CLICKHOUSE_HOST', 'localhost'),
      port: ENV.fetch('CLICKHOUSE_PORT', 8123).to_i,
      database: ENV.fetch('CLICKHOUSE_DATABASE', 'clickhouse_ruby_test')
    }
  end
end

RSpec.configure do |config|
  config.before(:suite) do
    ClickhouseHelper.setup_test_database
  end

  config.after(:suite) do
    ClickhouseHelper.teardown_test_database if ENV['CLEANUP_DATABASE'] == 'true'
  end

  config.around(:each, :integration) do |example|
    ClickhouseHelper.truncate_tables
    example.run
  end
end
```

### Fixture Data

```sql
-- spec/fixtures/init.sql
CREATE DATABASE IF NOT EXISTS clickhouse_ruby_test;

-- Standard test tables
CREATE TABLE IF NOT EXISTS clickhouse_ruby_test.test_types (
  id UInt64,
  string_col String,
  int_col Int32,
  uint_col UInt64,
  float_col Float64,
  date_col Date,
  datetime_col DateTime,
  array_col Array(String),
  map_col Map(String, UInt64),
  nullable_col Nullable(String)
) ENGINE = MergeTree ORDER BY id;

CREATE TABLE IF NOT EXISTS clickhouse_ruby_test.test_events (
  event_id UInt64,
  event_type LowCardinality(String),
  user_id UInt64,
  properties String,
  created_at DateTime
) ENGINE = MergeTree
PARTITION BY toYYYYMM(created_at)
ORDER BY (created_at, event_id);
```

## Shared Examples

```ruby
# spec/support/shared_examples.rb

RSpec.shared_examples 'a ClickHouse type' do
  it 'responds to #cast' do
    expect(subject).to respond_to(:cast)
  end

  it 'responds to #deserialize' do
    expect(subject).to respond_to(:deserialize)
  end

  it 'responds to #serialize' do
    expect(subject).to respond_to(:serialize)
  end

  it 'roundtrips values correctly' do
    test_values.each do |value|
      serialized = subject.serialize(value)
      deserialized = subject.deserialize(serialized)
      expect(deserialized).to eq(value)
    end
  end
end

RSpec.shared_examples 'a connection adapter method' do
  it 'does not silently fail' do
    expect { subject }.not_to raise_error
    # OR
    expect { subject }.to raise_error(expected_error_class)
  end

  it 'returns expected type' do
    expect(subject).to be_a(expected_return_type)
  end
end
```

## Coverage Requirements

| Component | Minimum Coverage |
|-----------|------------------|
| Core (`lib/clickhouse_ruby/*.rb`) | 95% |
| Types (`lib/clickhouse_ruby/types/`) | 95% |
| ActiveRecord (`lib/clickhouse_ruby/active_record/`) | 85% |
| Integration tests | 80% |
| **Overall** | **90%** |

```ruby
# spec/spec_helper.rb
require 'simplecov'

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'

  add_group 'Core', 'lib/clickhouse_ruby'
  add_group 'Types', 'lib/clickhouse_ruby/types'
  add_group 'ActiveRecord', 'lib/clickhouse_ruby/active_record'

  minimum_coverage 90
  minimum_coverage_by_file 80
end
```

## Test Commands

```bash
# Run all tests
bundle exec rspec

# Run unit tests only
bundle exec rspec spec/unit

# Run integration tests (requires ClickHouse)
bundle exec rspec spec/integration

# Run with coverage
COVERAGE=true bundle exec rspec

# Run specific test file
bundle exec rspec spec/unit/clickhouse_ruby/types/parser_spec.rb

# Run with documentation format
bundle exec rspec --format documentation

# Run failing tests first
bundle exec rspec --only-failures

# Record new VCR cassettes
RECORD_CASSETTES=true bundle exec rspec spec/integration
```
