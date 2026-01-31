# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickhouseRuby::ConnectionPool do
  let(:config) do
    ClickhouseRuby::Configuration.new.tap do |c|
      c.host = 'localhost'
      c.port = 8123
      c.database = 'default'
      c.pool_size = 3
      c.pool_timeout = 5
    end
  end

  let(:mock_connection) { instance_double(ClickhouseRuby::Connection) }

  before do
    allow(ClickhouseRuby::Connection).to receive(:new).and_return(mock_connection)
    allow(mock_connection).to receive(:connect).and_return(mock_connection)
    allow(mock_connection).to receive(:disconnect)
    allow(mock_connection).to receive(:healthy?).and_return(true)
    allow(mock_connection).to receive(:stale?).and_return(false)
    allow(mock_connection).to receive(:ping).and_return(true)
  end

  describe '#initialize' do
    it 'sets pool size from config' do
      pool = described_class.new(config)
      expect(pool.size).to eq(3)
    end

    it 'sets timeout from config' do
      pool = described_class.new(config)
      expect(pool.timeout).to eq(5)
    end

    it 'allows overriding size' do
      pool = described_class.new(config, size: 10)
      expect(pool.size).to eq(10)
    end

    it 'allows overriding timeout' do
      pool = described_class.new(config, timeout: 30)
      expect(pool.timeout).to eq(30)
    end
  end

  describe '#with_connection' do
    let(:pool) { described_class.new(config) }

    it 'yields a connection' do
      expect { |b| pool.with_connection(&b) }.to yield_with_args(mock_connection)
    end

    it 'returns the block result' do
      result = pool.with_connection { 'result' }
      expect(result).to eq('result')
    end

    it 'automatically returns the connection' do
      pool.with_connection { }
      expect(pool.available_count).to eq(1)
      expect(pool.in_use_count).to eq(0)
    end

    it 'returns the connection even if block raises' do
      expect { pool.with_connection { raise 'error' } }.to raise_error('error')
      expect(pool.available_count).to eq(1)
      expect(pool.in_use_count).to eq(0)
    end
  end

  describe '#checkout' do
    let(:pool) { described_class.new(config) }

    it 'returns a connection' do
      conn = pool.checkout
      expect(conn).to eq(mock_connection)
    end

    it 'creates a new connection on first checkout' do
      expect(ClickhouseRuby::Connection).to receive(:new)
      pool.checkout
    end

    it 'tracks connection as in use' do
      pool.checkout
      expect(pool.in_use_count).to eq(1)
    end

    it 'increments total checkouts' do
      pool.checkout
      expect(pool.stats[:total_checkouts]).to eq(1)
    end

    context 'when pool is at capacity' do
      before do
        config.pool_size = 1
        config.pool_timeout = 0.1
      end

      let(:small_pool) { described_class.new(config) }

      it 'raises PoolTimeout when no connections available' do
        small_pool.checkout # Take the only connection
        expect { small_pool.checkout }.to raise_error(ClickhouseRuby::PoolTimeout)
      end

      it 'increments timeout counter' do
        small_pool.checkout
        expect { small_pool.checkout }.to raise_error(ClickhouseRuby::PoolTimeout)
        expect(small_pool.stats[:total_timeouts]).to eq(1)
      end
    end

    context 'when checking out unhealthy connection from pool' do
      before do
        # First, get a connection into the available pool
        conn = pool.checkout
        pool.checkin(conn)
        # Now make it unhealthy for the next checkout
        allow(mock_connection).to receive(:healthy?).and_return(false)
      end

      it 'disconnects unhealthy connection and creates new one' do
        expect(mock_connection).to receive(:disconnect).at_least(:once)
        pool.checkout
      end
    end
  end

  describe '#checkin' do
    let(:pool) { described_class.new(config) }

    it 'returns connection to available pool' do
      conn = pool.checkout
      pool.checkin(conn)
      expect(pool.available_count).to eq(1)
      expect(pool.in_use_count).to eq(0)
    end

    it 'handles nil connection' do
      expect { pool.checkin(nil) }.not_to raise_error
    end

    context 'when connection is unhealthy' do
      it 'disconnects unhealthy connection' do
        conn = pool.checkout
        # Make unhealthy after checkout, before checkin
        allow(mock_connection).to receive(:healthy?).and_return(false)
        expect(mock_connection).to receive(:disconnect)
        pool.checkin(conn)
      end

      it 'does not return unhealthy connection to pool' do
        conn = pool.checkout
        # Make unhealthy after checkout, before checkin
        allow(mock_connection).to receive(:healthy?).and_return(false)
        pool.checkin(conn)
        expect(pool.available_count).to eq(0)
      end
    end

    context 'when connection is stale' do
      it 'disconnects stale connection' do
        conn = pool.checkout
        # Make stale after checkout, before checkin
        allow(mock_connection).to receive(:stale?).and_return(true)
        expect(mock_connection).to receive(:disconnect)
        pool.checkin(conn)
      end
    end

    context 'when disconnect raises an error' do
      let(:logger) { instance_double(Logger) }

      before do
        config.logger = logger
        allow(logger).to receive(:warn)
      end

      it 'logs the error instead of raising' do
        conn = pool.checkout
        # Make unhealthy after checkout, then make disconnect fail
        allow(mock_connection).to receive(:healthy?).and_return(false)
        allow(mock_connection).to receive(:disconnect).and_raise(StandardError.new('disconnect failed'))
        expect(logger).to receive(:warn).with(/Disconnect error/)
        pool.checkin(conn)
      end
    end
  end

  describe '#available_count' do
    let(:pool) { described_class.new(config) }

    it 'returns 0 initially' do
      expect(pool.available_count).to eq(0)
    end

    it 'returns count of available connections' do
      conn = pool.checkout
      pool.checkin(conn)
      expect(pool.available_count).to eq(1)
    end
  end

  describe '#in_use_count' do
    let(:pool) { described_class.new(config) }

    it 'returns 0 initially' do
      expect(pool.in_use_count).to eq(0)
    end

    it 'returns count of in-use connections' do
      pool.checkout
      expect(pool.in_use_count).to eq(1)
    end
  end

  describe '#total_count' do
    let(:pool) { described_class.new(config) }

    it 'returns 0 initially' do
      expect(pool.total_count).to eq(0)
    end

    it 'returns total connections created' do
      pool.checkout
      expect(pool.total_count).to eq(1)
    end
  end

  describe '#exhausted?' do
    let(:pool) { described_class.new(config) }

    it 'returns false initially' do
      expect(pool.exhausted?).to be false
    end

    it 'returns true when all connections are in use' do
      config.pool_size.times { pool.checkout }
      expect(pool.exhausted?).to be true
    end

    it 'returns false when connections are available' do
      conn = pool.checkout
      pool.checkin(conn)
      expect(pool.exhausted?).to be false
    end
  end

  describe '#shutdown' do
    let(:pool) { described_class.new(config) }

    it 'disconnects all connections' do
      pool.checkout
      expect(mock_connection).to receive(:disconnect)
      pool.shutdown
    end

    it 'clears all pools' do
      conn = pool.checkout
      pool.checkin(conn)
      pool.shutdown
      expect(pool.available_count).to eq(0)
      expect(pool.in_use_count).to eq(0)
      expect(pool.total_count).to eq(0)
    end

    context 'when disconnect raises an error' do
      let(:logger) { instance_double(Logger) }

      before do
        config.logger = logger
        allow(mock_connection).to receive(:disconnect).and_raise(StandardError.new('shutdown error'))
        allow(logger).to receive(:warn)
      end

      it 'logs the error and continues' do
        pool.checkout
        expect(logger).to receive(:warn).with(/Disconnect error/)
        pool.shutdown
      end
    end
  end

  describe '#cleanup' do
    let(:pool) { described_class.new(config) }

    before do
      conn = pool.checkout
      pool.checkin(conn)
    end

    context 'when connections are healthy and fresh' do
      it 'does not remove connections' do
        removed = pool.cleanup
        expect(removed).to eq(0)
        expect(pool.available_count).to eq(1)
      end
    end

    context 'when connections are stale' do
      it 'removes stale connections' do
        # Make stale before cleanup
        allow(mock_connection).to receive(:stale?).and_return(true)
        removed = pool.cleanup
        expect(removed).to eq(1)
        expect(pool.available_count).to eq(0)
      end
    end

    context 'when connections are unhealthy' do
      it 'removes unhealthy connections' do
        # Make unhealthy before cleanup
        allow(mock_connection).to receive(:healthy?).and_return(false)
        removed = pool.cleanup
        expect(removed).to eq(1)
        expect(pool.available_count).to eq(0)
      end
    end

    context 'when disconnect raises an error during cleanup' do
      let(:logger) { instance_double(Logger) }

      before do
        config.logger = logger
        allow(logger).to receive(:warn)
      end

      it 'logs the error and continues' do
        # Make stale and make disconnect fail
        allow(mock_connection).to receive(:stale?).and_return(true)
        allow(mock_connection).to receive(:disconnect).and_raise(StandardError.new('cleanup error'))
        expect(logger).to receive(:warn).with(/Disconnect error/)
        pool.cleanup
      end
    end
  end

  describe '#health_check' do
    let(:pool) { described_class.new(config) }

    before do
      conn = pool.checkout
      pool.checkin(conn)
    end

    it 'returns health status' do
      status = pool.health_check
      expect(status).to include(:available, :in_use, :total, :capacity, :healthy, :unhealthy)
    end

    it 'pings available connections' do
      expect(mock_connection).to receive(:ping).and_return(true)
      status = pool.health_check
      expect(status[:healthy]).to eq(1)
      expect(status[:unhealthy]).to eq(0)
    end

    context 'with unhealthy connection' do
      before do
        allow(mock_connection).to receive(:ping).and_return(false)
      end

      it 'counts unhealthy connections' do
        status = pool.health_check
        expect(status[:healthy]).to eq(0)
        expect(status[:unhealthy]).to eq(1)
      end
    end
  end

  describe '#stats' do
    let(:pool) { described_class.new(config) }

    it 'returns pool statistics' do
      stats = pool.stats
      expect(stats).to include(
        :size,
        :available,
        :in_use,
        :total_connections,
        :total_checkouts,
        :total_timeouts,
        :uptime_seconds
      )
    end

    it 'tracks checkouts' do
      pool.checkout
      expect(pool.stats[:total_checkouts]).to eq(1)
    end
  end

  describe '#inspect' do
    let(:pool) { described_class.new(config) }

    it 'returns a descriptive string' do
      expect(pool.inspect).to include('ConnectionPool')
      expect(pool.inspect).to include('size=3')
    end
  end

  describe 'thread safety' do
    let(:pool) { described_class.new(config) }

    it 'handles concurrent checkouts' do
      config.pool_size = 5

      threads = 5.times.map do
        Thread.new do
          conn = pool.checkout
          sleep(0.01)
          pool.checkin(conn)
        end
      end

      threads.each(&:join)
      expect(pool.available_count).to eq(5)
      expect(pool.in_use_count).to eq(0)
    end

    it 'handles with_connection from multiple threads' do
      config.pool_size = 5
      results = []

      threads = 5.times.map do |i|
        Thread.new do
          pool.with_connection do |_conn|
            sleep(0.01)
            results << i
          end
        end
      end

      threads.each(&:join)
      expect(results.size).to eq(5)
    end
  end
end
