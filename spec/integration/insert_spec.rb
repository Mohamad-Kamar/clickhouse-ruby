# frozen_string_literal: true

require 'spec_helper'

# Integration tests for INSERT operations
#
# These tests verify bulk inserts, various data types,
# and proper error handling during inserts.
#
RSpec.describe 'Insert Operations', :integration do
  include_context 'integration test'

  describe 'basic inserts' do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_basic_insert (
          id UInt64,
          name String,
          value Int32
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute('DROP TABLE IF EXISTS test_basic_insert')
    end

    it 'inserts a single row' do
      client.insert('test_basic_insert', [{ id: 1, name: 'test', value: 100 }])

      result = client.execute('SELECT * FROM test_basic_insert WHERE id = 1').first
      expect(result['id']).to eq(1)
      expect(result['name']).to eq('test')
      expect(result['value']).to eq(100)
    end

    it 'inserts multiple rows' do
      rows = (1..10).map { |i| { id: i, name: "row_#{i}", value: i * 10 } }
      client.insert('test_basic_insert', rows)

      result = client.execute('SELECT count() as cnt FROM test_basic_insert')
      expect(result.first['cnt']).to eq(10)
    end

    it 'handles empty insert' do
      # Inserting empty array should not raise error
      expect { client.insert('test_basic_insert', []) }.not_to raise_error
    end
  end

  describe 'bulk inserts' do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_bulk_insert (
          id UInt64,
          data String,
          timestamp DateTime DEFAULT now()
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute('DROP TABLE IF EXISTS test_bulk_insert')
    end

    it 'inserts 1000 rows efficiently', :slow do
      rows = (1..1000).map { |i| { id: i, data: "data_#{i}" } }

      expect { client.insert('test_bulk_insert', rows) }.not_to raise_error

      result = client.execute('SELECT count() as cnt FROM test_bulk_insert')
      expect(result.first['cnt']).to eq(1000)
    end

    it 'inserts 10000 rows efficiently', :slow do
      rows = (1..10_000).map { |i| { id: i, data: "data_#{i}" } }

      expect { client.insert('test_bulk_insert', rows) }.not_to raise_error

      result = client.execute('SELECT count() as cnt FROM test_bulk_insert')
      expect(result.first['cnt']).to eq(10_000)
    end
  end

  describe 'insert with complex types' do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_complex_insert (
          id UInt64,
          tags Array(String),
          properties Map(String, Int32),
          coordinates Tuple(Float64, Float64),
          nullable_value Nullable(Int32)
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute('DROP TABLE IF EXISTS test_complex_insert')
    end

    it 'inserts arrays' do
      client.insert('test_complex_insert', [{
        id: 1,
        tags: %w[tag1 tag2 tag3],
        properties: {},
        coordinates: [0.0, 0.0],
        nullable_value: nil
      }])

      result = client.execute('SELECT tags FROM test_complex_insert WHERE id = 1').first
      expect(result['tags']).to eq(%w[tag1 tag2 tag3])
    end

    it 'inserts maps' do
      client.insert('test_complex_insert', [{
        id: 2,
        tags: [],
        properties: { 'a' => 1, 'b' => 2, 'c' => 3 },
        coordinates: [0.0, 0.0],
        nullable_value: nil
      }])

      result = client.execute('SELECT properties FROM test_complex_insert WHERE id = 2').first
      expect(result['properties']).to eq({ 'a' => 1, 'b' => 2, 'c' => 3 })
    end

    it 'inserts tuples' do
      client.insert('test_complex_insert', [{
        id: 3,
        tags: [],
        properties: {},
        coordinates: [40.7128, -74.0060],  # NYC coordinates
        nullable_value: nil
      }])

      result = client.execute('SELECT coordinates FROM test_complex_insert WHERE id = 3').first
      expect(result['coordinates'][0]).to be_within(0.001).of(40.7128)
      expect(result['coordinates'][1]).to be_within(0.001).of(-74.006)
    end

    it 'inserts nullable values as null' do
      client.insert('test_complex_insert', [{
        id: 4,
        tags: [],
        properties: {},
        coordinates: [0.0, 0.0],
        nullable_value: nil
      }])

      result = client.execute('SELECT nullable_value FROM test_complex_insert WHERE id = 4').first
      expect(result['nullable_value']).to be_nil
    end

    it 'inserts nullable values as non-null' do
      client.insert('test_complex_insert', [{
        id: 5,
        tags: [],
        properties: {},
        coordinates: [0.0, 0.0],
        nullable_value: 42
      }])

      result = client.execute('SELECT nullable_value FROM test_complex_insert WHERE id = 5').first
      expect(result['nullable_value']).to eq(42)
    end
  end

  describe 'insert error handling' do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_insert_errors (
          id UInt64,
          required_field String,
          int_field Int32
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute('DROP TABLE IF EXISTS test_insert_errors')
    end

    it 'raises error for nonexistent table' do
      expect {
        client.insert('nonexistent_table_xyz', [{ id: 1 }])
      }.to raise_error(ClickhouseRuby::QueryError)
    end

    it 'raises error for type mismatch' do
      expect {
        client.insert('test_insert_errors', [{
          id: 'not_a_number',  # Should be UInt64
          required_field: 'test',
          int_field: 1
        }])
      }.to raise_error(ClickhouseRuby::Error)
    end

    it 'does not silently fail on insert errors' do
      # This is important - we must not lose data silently
      expect {
        client.insert('test_insert_errors', [{
          id: 1,
          required_field: 'test',
          int_field: 'not_an_integer'
        }])
      }.to raise_error(ClickhouseRuby::Error)
    end
  end

  describe 'insert with special characters' do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_special_chars (
          id UInt64,
          text String
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute('DROP TABLE IF EXISTS test_special_chars')
    end

    it 'handles quotes in strings' do
      client.insert('test_special_chars', [{
        id: 1,
        text: "It's a test with 'quotes'"
      }])

      result = client.execute('SELECT text FROM test_special_chars WHERE id = 1').first
      expect(result['text']).to eq("It's a test with 'quotes'")
    end

    it 'handles backslashes' do
      client.insert('test_special_chars', [{
        id: 2,
        text: 'Path: C:\\Users\\Test'
      }])

      result = client.execute('SELECT text FROM test_special_chars WHERE id = 2').first
      expect(result['text']).to eq('Path: C:\\Users\\Test')
    end

    it 'handles newlines' do
      client.insert('test_special_chars', [{
        id: 3,
        text: "Line 1\nLine 2\nLine 3"
      }])

      result = client.execute('SELECT text FROM test_special_chars WHERE id = 3').first
      expect(result['text']).to eq("Line 1\nLine 2\nLine 3")
    end

    it 'handles unicode characters' do
      client.insert('test_special_chars', [{
        id: 4,
        text: 'Unicode: \u4e2d\u6587 \u0420\u0443\u0441\u0441\u043a\u0438\u0439'
      }])

      result = client.execute('SELECT text FROM test_special_chars WHERE id = 4').first
      expect(result['text']).to include('Unicode:')
    end

    it 'handles empty strings' do
      client.insert('test_special_chars', [{
        id: 5,
        text: ''
      }])

      result = client.execute('SELECT text FROM test_special_chars WHERE id = 5').first
      expect(result['text']).to eq('')
    end
  end
end
