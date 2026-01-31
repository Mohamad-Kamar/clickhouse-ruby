# frozen_string_literal: true

require 'spec_helper'

# Only run these tests if ActiveRecord is available
# Guard must be at file level since constant resolution happens at parse time
return unless defined?(ActiveRecord) && defined?(ClickhouseRuby::ActiveRecord::ConnectionAdapter)

RSpec.describe ClickhouseRuby::ActiveRecord::ConnectionAdapter do
  let(:config) do
    {
      host: 'localhost',
      port: 8123,
      database: 'test_db',
      username: 'default',
      password: '',
      ssl: false,
      pool: 5
    }
  end

  let(:mock_client) { instance_double(ClickhouseRuby::Client) }
  let(:mock_result) { instance_double(ClickhouseRuby::Result, empty?: false, first: { 'count' => 1 }) }

  before do
    allow(ClickhouseRuby::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:execute).and_return(mock_result)
    allow(mock_client).to receive(:close)
  end

  describe '.new_client' do
    it 'creates a ClickhouseRuby client with correct configuration' do
      expect(ClickhouseRuby::Client).to receive(:new) do |config|
        expect(config.host).to eq('localhost')
        expect(config.port).to eq(8123)
        expect(config.database).to eq('test_db')
        mock_client
      end

      described_class.new_client(config)
    end

    it 'sets SSL verification enabled by default' do
      expect(ClickhouseRuby::Client).to receive(:new) do |c|
        expect(c.ssl_verify).to be true
        mock_client
      end

      described_class.new_client(config.merge(ssl: true))
    end

    it 'allows disabling SSL verification explicitly' do
      expect(ClickhouseRuby::Client).to receive(:new) do |c|
        expect(c.ssl_verify).to be false
        mock_client
      end

      described_class.new_client(config.merge(ssl: true, ssl_verify: false))
    end
  end

  describe '#adapter_name' do
    let(:adapter) { described_class.new(nil, nil, nil, config) }

    it 'returns Clickhouse' do
      expect(adapter.adapter_name).to eq('Clickhouse')
    end
  end

  describe '#native_database_types' do
    let(:adapter) { described_class.new(nil, nil, nil, config) }

    it 'returns type mapping' do
      types = adapter.native_database_types
      expect(types[:string]).to eq({ name: 'String' })
      expect(types[:integer]).to eq({ name: 'Int32' })
      expect(types[:bigint]).to eq({ name: 'Int64' })
      expect(types[:float]).to eq({ name: 'Float32' })
      expect(types[:datetime]).to eq({ name: 'DateTime' })
      expect(types[:date]).to eq({ name: 'Date' })
      expect(types[:boolean]).to eq({ name: 'UInt8' })
      expect(types[:uuid]).to eq({ name: 'UUID' })
    end
  end

  describe 'connection management' do
    let(:adapter) { described_class.new(nil, nil, nil, config) }

    describe '#connect' do
      it 'creates a new client' do
        expect(ClickhouseRuby::Client).to receive(:new).and_return(mock_client)
        adapter.connect
      end
    end

    describe '#connected?' do
      it 'returns false before connection' do
        expect(adapter.connected?).to be false
      end

      it 'returns true after connection' do
        adapter.connect
        expect(adapter.connected?).to be true
      end
    end

    describe '#active?' do
      before do
        adapter.connect
        allow(mock_result).to receive(:error?).and_return(false)
      end

      it 'returns true when connected and server responds' do
        expect(adapter.active?).to be true
      end

      it 'returns false when not connected' do
        adapter.disconnect!
        expect(adapter.active?).to be false
      end

      it 'returns false when query fails' do
        allow(mock_client).to receive(:execute).and_raise(ClickhouseRuby::ConnectionError)
        expect(adapter.active?).to be false
      end
    end

    describe '#disconnect!' do
      before { adapter.connect }

      it 'closes the client' do
        expect(mock_client).to receive(:close)
        adapter.disconnect!
      end

      it 'marks as disconnected' do
        adapter.disconnect!
        expect(adapter.connected?).to be false
      end
    end

    describe '#reconnect!' do
      before { adapter.connect }

      it 'disconnects and reconnects' do
        expect(adapter).to receive(:disconnect!).and_call_original
        expect(adapter).to receive(:connect).and_call_original
        adapter.reconnect!
      end
    end
  end

  describe 'ClickHouse capabilities' do
    let(:adapter) { described_class.new(nil, nil, nil, config) }

    it 'does not support DDL transactions' do
      expect(adapter.supports_ddl_transactions?).to be false
    end

    it 'does not support savepoints' do
      expect(adapter.supports_savepoints?).to be false
    end

    it 'does not support transaction isolation' do
      expect(adapter.supports_transaction_isolation?).to be false
    end

    it 'does not support INSERT RETURNING' do
      expect(adapter.supports_insert_returning?).to be false
    end

    it 'does not support foreign keys' do
      expect(adapter.supports_foreign_keys?).to be false
    end

    it 'does not support check constraints' do
      expect(adapter.supports_check_constraints?).to be false
    end

    it 'does not support partial indexes' do
      expect(adapter.supports_partial_index?).to be false
    end

    it 'does not support expression indexes' do
      expect(adapter.supports_expression_index?).to be false
    end

    it 'does not support views' do
      expect(adapter.supports_views?).to be false
    end

    it 'supports datetime with precision' do
      expect(adapter.supports_datetime_with_precision?).to be true
    end

    it 'supports JSON' do
      expect(adapter.supports_json?).to be true
    end

    it 'does not support comments' do
      expect(adapter.supports_comments?).to be false
    end

    it 'does not support bulk alter' do
      expect(adapter.supports_bulk_alter?).to be false
    end

    it 'supports explain' do
      expect(adapter.supports_explain?).to be true
    end
  end

  describe 'query execution' do
    let(:adapter) { described_class.new(nil, nil, nil, config) }

    before do
      adapter.connect
      allow(mock_result).to receive(:error?).and_return(false)
    end

    describe '#execute' do
      it 'executes query through client' do
        expect(mock_client).to receive(:execute).with('SELECT 1')
        adapter.execute('SELECT 1')
      end

      it 'returns result' do
        expect(adapter.execute('SELECT 1')).to eq(mock_result)
      end

      context 'when query fails' do
        before do
          allow(mock_client).to receive(:execute).and_raise(
            ClickhouseRuby::QueryError.new('Table not found', code: 60)
          )
        end

        it 'raises QueryError' do
          expect { adapter.execute('SELECT * FROM missing') }.to raise_error(ClickhouseRuby::QueryError)
        end
      end
    end

    describe '#exec_delete' do
      it 'converts DELETE to ALTER TABLE DELETE' do
        expect(mock_client).to receive(:execute).with('ALTER TABLE events DELETE WHERE id = 1')
        adapter.exec_delete('DELETE FROM events WHERE id = 1')
      end

      it 'handles DELETE without WHERE' do
        expect(mock_client).to receive(:execute).with('ALTER TABLE events DELETE WHERE 1=1')
        adapter.exec_delete('DELETE FROM events')
      end

      it 'passes through ALTER TABLE DELETE unchanged' do
        expect(mock_client).to receive(:execute).with('ALTER TABLE events DELETE WHERE id = 1')
        adapter.exec_delete('ALTER TABLE events DELETE WHERE id = 1')
      end

      context 'when delete fails' do
        before do
          allow(mock_client).to receive(:execute).and_raise(
            ClickhouseRuby::QueryError.new('Delete failed')
          )
        end

        it 'raises QueryError - never silently fails' do
          expect { adapter.exec_delete('DELETE FROM events WHERE id = 1') }.to raise_error(ClickhouseRuby::QueryError)
        end
      end
    end

    describe '#exec_update' do
      it 'converts UPDATE to ALTER TABLE UPDATE' do
        expect(mock_client).to receive(:execute).with("ALTER TABLE events UPDATE status = 'done' WHERE id = 1")
        adapter.exec_update("UPDATE events SET status = 'done' WHERE id = 1")
      end

      it 'handles UPDATE without WHERE' do
        expect(mock_client).to receive(:execute).with("ALTER TABLE events UPDATE status = 'done' WHERE 1=1")
        adapter.exec_update("UPDATE events SET status = 'done'")
      end

      context 'when update fails' do
        before do
          allow(mock_client).to receive(:execute).and_raise(
            ClickhouseRuby::QueryError.new('Update failed')
          )
        end

        it 'raises QueryError - never silently fails' do
          expect { adapter.exec_update("UPDATE events SET status = 'done' WHERE id = 1") }.to raise_error(ClickhouseRuby::QueryError)
        end
      end
    end

    describe '#exec_insert' do
      it 'executes insert' do
        expect(mock_client).to receive(:execute).with("INSERT INTO events (id) VALUES (1)")
        adapter.exec_insert("INSERT INTO events (id) VALUES (1)")
      end

      it 'returns nil (ClickHouse does not return IDs)' do
        expect(adapter.exec_insert("INSERT INTO events (id) VALUES (1)")).to be_nil
      end
    end
  end

  describe 'transaction methods (no-op for ClickHouse)' do
    let(:adapter) { described_class.new(nil, nil, nil, config) }

    describe '#begin_db_transaction' do
      it 'is a no-op' do
        expect { adapter.begin_db_transaction }.not_to raise_error
      end
    end

    describe '#commit_db_transaction' do
      it 'is a no-op' do
        expect { adapter.commit_db_transaction }.not_to raise_error
      end
    end

    describe '#exec_rollback_db_transaction' do
      let(:logger) { instance_double(Logger) }

      before do
        allow(adapter).to receive(:instance_variable_get).with(:@logger).and_return(logger)
        allow(logger).to receive(:warn)
      end

      it 'is a no-op that logs a warning' do
        expect { adapter.exec_rollback_db_transaction }.not_to raise_error
      end
    end
  end

  describe 'quoting' do
    let(:adapter) { described_class.new(nil, nil, nil, config) }

    describe '#quote_column_name' do
      it 'uses backticks' do
        expect(adapter.quote_column_name('column')).to eq('`column`')
      end

      it 'escapes backticks in name' do
        expect(adapter.quote_column_name('col`umn')).to eq('`col``umn`')
      end

      it 'handles symbols' do
        expect(adapter.quote_column_name(:column)).to eq('`column`')
      end
    end

    describe '#quote_table_name' do
      it 'uses backticks' do
        expect(adapter.quote_table_name('table')).to eq('`table`')
      end

      it 'escapes backticks in name' do
        expect(adapter.quote_table_name('ta`ble')).to eq('`ta``ble`')
      end
    end

    describe '#quote_string' do
      it 'escapes backslashes' do
        expect(adapter.quote_string('back\\slash')).to include('\\\\')
      end

      it 'escapes single quotes' do
        expect(adapter.quote_string("it's")).to include("\\'")
      end
    end
  end

  describe '#arel_visitor' do
    let(:adapter) { described_class.new(nil, nil, nil, config) }

    it 'returns an ArelVisitor' do
      expect(adapter.arel_visitor).to be_a(ClickhouseRuby::ActiveRecord::ArelVisitor)
    end

    it 'caches the visitor' do
      visitor1 = adapter.arel_visitor
      visitor2 = adapter.arel_visitor
      expect(visitor1).to equal(visitor2)
    end
  end
end
