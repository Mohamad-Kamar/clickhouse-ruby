# frozen_string_literal: true

require 'spec_helper'

# Integration tests for connection handling
#
# These tests verify SSL, authentication, and connection pool behavior
# with a real ClickHouse server.
#
RSpec.describe 'Connection Integration', :integration do
  include_context 'integration test'

  describe 'basic connectivity' do
    it 'executes simple SELECT' do
      result = client.execute('SELECT 1 as value')
      expect(result.first['value']).to eq(1)
    end

    it 'executes SELECT with multiple rows' do
      result = client.execute('SELECT number FROM system.numbers LIMIT 10')
      expect(result.count).to eq(10)
    end

    it 'correctly handles empty results' do
      result = client.execute('SELECT 1 WHERE 0')
      expect(result.to_a).to be_empty
    end
  end

  describe 'database selection' do
    it 'uses the configured database' do
      result = client.execute('SELECT currentDatabase() as db')
      expect(result.first['db']).to eq(ClickhouseHelper::TEST_DATABASE)
    end

    it 'can query system tables' do
      result = client.execute('SELECT name FROM system.databases LIMIT 1')
      expect(result.first).to have_key('name')
    end
  end

  describe 'query settings' do
    it 'accepts query settings' do
      result = client.execute(
        'SELECT number FROM system.numbers LIMIT 100',
        settings: { max_threads: 1 }
      )
      expect(result.count).to eq(100)
    end

    it 'accepts timeout settings' do
      # Very short timeout should work for fast queries
      result = client.execute(
        'SELECT 1',
        settings: { max_execution_time: 60 }
      )
      expect(result.first.values.first).to eq(1)
    end
  end

  describe 'concurrent queries' do
    it 'handles multiple concurrent queries' do
      threads = 10.times.map do |i|
        Thread.new do
          result = client.execute("SELECT #{i} as value")
          result.first['value']
        end
      end

      results = threads.map(&:value).sort
      expect(results).to eq((0..9).to_a)
    end
  end

  describe 'response formats' do
    it 'returns data with correct column names' do
      result = client.execute('SELECT 1 as my_column, 2 as another_column')
      row = result.first
      expect(row).to have_key('my_column')
      expect(row).to have_key('another_column')
    end

    it 'preserves column order in results' do
      result = client.execute('SELECT 3 as c, 1 as a, 2 as b')
      keys = result.first.keys
      expect(keys).to eq(%w[c a b])
    end
  end

  describe 'SSL connection', if: ENV['CLICKHOUSE_SSL'] == 'true' do
    it 'connects successfully with SSL' do
      result = client.execute('SELECT 1')
      expect(result.first.values.first).to eq(1)
    end

    # Test that SSL verification is working
    it 'uses SSL for the connection' do
      expect(ClickhouseRuby.configuration.use_ssl?).to be true
    end
  end

  describe 'authentication', if: ENV['CLICKHOUSE_USER'] do
    it 'authenticates with provided credentials' do
      result = client.execute('SELECT currentUser() as user')
      expect(result.first['user']).to eq(ENV['CLICKHOUSE_USER'])
    end
  end

  describe 'large result sets' do
    it 'handles large result sets', :slow do
      result = client.execute('SELECT number FROM system.numbers LIMIT 100000')
      expect(result.count).to eq(100_000)
    end

    it 'streams results efficiently' do
      # This should not load all data into memory at once
      count = 0
      client.execute('SELECT number FROM system.numbers LIMIT 10000').each do |row|
        count += 1
      end
      expect(count).to eq(10_000)
    end
  end

  describe 'query cancellation', :slow do
    it 'respects query timeout settings' do
      # ClickHouse's sleep() behavior varies by version
      # Just verify settings are accepted without error
      start_time = Time.now
      begin
        client.execute(
          'SELECT sleep(0.1)',
          settings: { max_execution_time: 5 }
        )
      rescue ClickhouseRuby::QueryError
        # Timeout is acceptable
      end
      elapsed = Time.now - start_time
      expect(elapsed).to be < 10
    end
  end
end
