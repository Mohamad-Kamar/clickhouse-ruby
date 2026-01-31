# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickhouseRuby::Result do
  describe '#initialize' do
    it 'stores columns' do
      result = described_class.new(columns: %w[id name], types: %w[UInt64 String], data: [])
      expect(result.columns).to eq(%w[id name])
    end

    it 'stores types' do
      result = described_class.new(columns: %w[id name], types: %w[UInt64 String], data: [])
      expect(result.types).to eq(%w[UInt64 String])
    end

    it 'freezes columns and types' do
      result = described_class.new(columns: %w[id name], types: %w[UInt64 String], data: [])
      expect(result.columns).to be_frozen
      expect(result.types).to be_frozen
    end

    it 'converts data to row hashes' do
      result = described_class.new(columns: %w[id name], types: %w[UInt64 String], data: [[1, 'Alice']])
      expect(result.rows).to eq([{ 'id' => 1, 'name' => 'Alice' }])
    end

    it 'deserializes values by default' do
      result = described_class.new(columns: ['value'], types: ['UInt64'], data: [['123']])
      expect(result.first['value']).to eq(123)
    end

    it 'skips deserialization when disabled' do
      result = described_class.new(columns: ['value'], types: ['UInt64'], data: [['123']], deserialize: false)
      expect(result.first['value']).to eq('123')
    end

    it 'stores statistics' do
      stats = { 'elapsed' => 0.05, 'rows_read' => 100, 'bytes_read' => 1024 }
      result = described_class.new(columns: [], types: [], data: [], statistics: stats)
      expect(result.elapsed_time).to eq(0.05)
      expect(result.rows_read).to eq(100)
      expect(result.bytes_read).to eq(1024)
    end
  end

  describe 'Enumerable interface' do
    let(:result) do
      described_class.new(
        columns: %w[id name],
        types: %w[UInt64 String],
        data: [[1, 'Alice'], [2, 'Bob'], [3, 'Charlie']]
      )
    end

    describe '#each' do
      it 'yields each row' do
        names = []
        result.each { |row| names << row['name'] }
        expect(names).to eq(%w[Alice Bob Charlie])
      end

      it 'returns an enumerator without block' do
        expect(result.each).to be_an(Enumerator)
      end
    end

    describe '#map' do
      it 'maps rows' do
        names = result.map { |row| row['name'] }
        expect(names).to eq(%w[Alice Bob Charlie])
      end
    end

    describe '#select' do
      it 'filters rows' do
        filtered = result.select { |row| row['id'] > 1 }
        expect(filtered.map { |r| r['name'] }).to eq(%w[Bob Charlie])
      end
    end

    describe '#to_a' do
      it 'returns all rows as array' do
        expect(result.to_a).to eq([
          { 'id' => 1, 'name' => 'Alice' },
          { 'id' => 2, 'name' => 'Bob' },
          { 'id' => 3, 'name' => 'Charlie' }
        ])
      end
    end
  end

  describe '#first' do
    it 'returns the first row' do
      result = described_class.new(
        columns: ['name'],
        types: ['String'],
        data: [['Alice'], ['Bob']]
      )
      expect(result.first).to eq({ 'name' => 'Alice' })
    end

    it 'returns nil for empty result' do
      result = described_class.new(columns: [], types: [], data: [])
      expect(result.first).to be_nil
    end
  end

  describe '#last' do
    it 'returns the last row' do
      result = described_class.new(
        columns: ['name'],
        types: ['String'],
        data: [['Alice'], ['Bob']]
      )
      expect(result.last).to eq({ 'name' => 'Bob' })
    end

    it 'returns nil for empty result' do
      result = described_class.new(columns: [], types: [], data: [])
      expect(result.last).to be_nil
    end
  end

  describe '#[]' do
    let(:result) do
      described_class.new(
        columns: ['name'],
        types: ['String'],
        data: [['Alice'], ['Bob'], ['Charlie']]
      )
    end

    it 'returns row at index' do
      expect(result[1]).to eq({ 'name' => 'Bob' })
    end

    it 'returns nil for out of bounds' do
      expect(result[10]).to be_nil
    end

    it 'supports negative indices' do
      expect(result[-1]).to eq({ 'name' => 'Charlie' })
    end
  end

  describe '#count' do
    it 'returns number of rows' do
      result = described_class.new(
        columns: ['name'],
        types: ['String'],
        data: [['Alice'], ['Bob']]
      )
      expect(result.count).to eq(2)
    end

    it 'returns 0 for empty result' do
      result = described_class.new(columns: [], types: [], data: [])
      expect(result.count).to eq(0)
    end
  end

  describe '#size' do
    it 'is an alias for count' do
      result = described_class.new(columns: ['name'], types: ['String'], data: [['Alice']])
      expect(result.size).to eq(result.count)
    end
  end

  describe '#length' do
    it 'is an alias for count' do
      result = described_class.new(columns: ['name'], types: ['String'], data: [['Alice']])
      expect(result.length).to eq(result.count)
    end
  end

  describe '#empty?' do
    it 'returns true for empty result' do
      result = described_class.new(columns: [], types: [], data: [])
      expect(result.empty?).to be true
    end

    it 'returns false for non-empty result' do
      result = described_class.new(columns: ['name'], types: ['String'], data: [['Alice']])
      expect(result.empty?).to be false
    end
  end

  describe '#column_values' do
    let(:result) do
      described_class.new(
        columns: %w[id name],
        types: %w[UInt64 String],
        data: [[1, 'Alice'], [2, 'Bob']]
      )
    end

    it 'returns all values for a column' do
      expect(result.column_values('name')).to eq(%w[Alice Bob])
    end

    it 'returns all values for id column' do
      expect(result.column_values('id')).to eq([1, 2])
    end

    it 'raises ArgumentError for unknown column' do
      expect { result.column_values('unknown') }.to raise_error(ArgumentError, /Unknown column/)
    end
  end

  describe '#column_types' do
    it 'returns hash of column names to types' do
      result = described_class.new(
        columns: %w[id name],
        types: %w[UInt64 String],
        data: []
      )
      expect(result.column_types).to eq({ 'id' => 'UInt64', 'name' => 'String' })
    end
  end

  describe '.empty' do
    it 'creates an empty result' do
      result = described_class.empty
      expect(result.columns).to eq([])
      expect(result.types).to eq([])
      expect(result.rows).to eq([])
    end
  end

  describe '.from_json_compact' do
    it 'parses JSONCompact response' do
      response_data = {
        'meta' => [
          { 'name' => 'id', 'type' => 'UInt64' },
          { 'name' => 'name', 'type' => 'String' }
        ],
        'data' => [
          [1, 'Alice'],
          [2, 'Bob']
        ],
        'statistics' => {
          'elapsed' => 0.001,
          'rows_read' => 2,
          'bytes_read' => 100
        }
      }

      result = described_class.from_json_compact(response_data)

      expect(result.columns).to eq(%w[id name])
      expect(result.types).to eq(%w[UInt64 String])
      expect(result.count).to eq(2)
      expect(result.first).to eq({ 'id' => 1, 'name' => 'Alice' })
      expect(result.elapsed_time).to eq(0.001)
    end

    it 'handles empty response' do
      response_data = {
        'meta' => [],
        'data' => [],
        'statistics' => {}
      }

      result = described_class.from_json_compact(response_data)
      expect(result.empty?).to be true
    end

    it 'handles missing fields' do
      response_data = {}

      result = described_class.from_json_compact(response_data)
      expect(result.columns).to eq([])
      expect(result.empty?).to be true
    end
  end

  describe '#inspect' do
    it 'returns a descriptive string' do
      result = described_class.new(
        columns: %w[id name],
        types: %w[UInt64 String],
        data: [[1, 'Alice']]
      )
      expect(result.inspect).to include('Result')
      expect(result.inspect).to include('columns')
      expect(result.inspect).to include('rows=1')
    end
  end

  describe 'type deserialization' do
    it 'deserializes integers' do
      result = described_class.new(columns: ['value'], types: ['Int32'], data: [['42']])
      expect(result.first['value']).to eq(42)
    end

    it 'deserializes floats' do
      result = described_class.new(columns: ['value'], types: ['Float64'], data: [['3.14']])
      expect(result.first['value']).to be_within(0.001).of(3.14)
    end

    it 'deserializes booleans' do
      result = described_class.new(columns: ['value'], types: ['Bool'], data: [[1]])
      expect(result.first['value']).to be true
    end

    it 'deserializes nullable values' do
      result = described_class.new(columns: ['value'], types: ['Nullable(String)'], data: [[nil]])
      expect(result.first['value']).to be_nil
    end

    it 'deserializes arrays' do
      result = described_class.new(columns: ['value'], types: ['Array(String)'], data: [[%w[a b c]]])
      expect(result.first['value']).to eq(%w[a b c])
    end
  end
end
