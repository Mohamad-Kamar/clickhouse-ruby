# frozen_string_literal: true

require "spec_helper"

# Integration tests for type handling with real ClickHouse
#
# These tests verify that our type system correctly handles
# real ClickHouse data, including complex nested types.
#
RSpec.describe "Type System Integration", :integration do
  include_context "integration test"

  describe "integer types" do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_integers_integration (
          int8_val Int8,
          int16_val Int16,
          int32_val Int32,
          int64_val Int64,
          uint8_val UInt8,
          uint16_val UInt16,
          uint32_val UInt32,
          uint64_val UInt64
        ) ENGINE = MergeTree() ORDER BY int32_val
      SQL
    end

    after do
      client.execute("DROP TABLE IF EXISTS test_integers_integration")
    end

    it "correctly handles all integer types" do
      client.insert("test_integers_integration", [{
        int8_val: -128,
        int16_val: -32_768,
        int32_val: -2_147_483_648,
        int64_val: -9_223_372_036_854_775_808,
        uint8_val: 255,
        uint16_val: 65_535,
        uint32_val: 4_294_967_295,
        uint64_val: 18_446_744_073_709_551_615,
      }],)

      result = client.execute("SELECT * FROM test_integers_integration").first

      expect(result["int8_val"]).to eq(-128)
      expect(result["int16_val"]).to eq(-32_768)
      expect(result["int32_val"]).to eq(-2_147_483_648)
      expect(result["int64_val"]).to eq(-9_223_372_036_854_775_808)
      expect(result["uint8_val"]).to eq(255)
      expect(result["uint16_val"]).to eq(65_535)
      expect(result["uint32_val"]).to eq(4_294_967_295)
      expect(result["uint64_val"]).to eq(18_446_744_073_709_551_615)
    end
  end

  describe "array types" do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_arrays_integration (
          id UInt64,
          int_array Array(Int32),
          string_array Array(String),
          nested_array Array(Array(Int32)),
          nullable_array Array(Nullable(Int32))
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute("DROP TABLE IF EXISTS test_arrays_integration")
    end

    it "correctly handles simple arrays" do
      client.insert("test_arrays_integration", [{
        id: 1,
        int_array: [1, 2, 3, 4, 5],
        string_array: %w[hello world],
        nested_array: [[1, 2], [3, 4]],
        nullable_array: [1, nil, 3],
      }],)

      result = client.execute("SELECT * FROM test_arrays_integration WHERE id = 1").first

      expect(result["int_array"]).to eq([1, 2, 3, 4, 5])
      expect(result["string_array"]).to eq(%w[hello world])
    end

    it "correctly handles nested arrays" do
      client.insert("test_arrays_integration", [{
        id: 2,
        int_array: [],
        string_array: [],
        nested_array: [[1, 2, 3], [4, 5, 6], [7, 8, 9]],
        nullable_array: [],
      }],)

      result = client.execute("SELECT nested_array FROM test_arrays_integration WHERE id = 2").first
      expect(result["nested_array"]).to eq([[1, 2, 3], [4, 5, 6], [7, 8, 9]])
    end

    it "correctly handles arrays with nullable elements" do
      client.insert("test_arrays_integration", [{
        id: 3,
        int_array: [],
        string_array: [],
        nested_array: [],
        nullable_array: [1, nil, 3, nil, 5],
      }],)

      result = client.execute("SELECT nullable_array FROM test_arrays_integration WHERE id = 3").first
      expect(result["nullable_array"]).to eq([1, nil, 3, nil, 5])
    end

    it "correctly handles empty arrays" do
      client.insert("test_arrays_integration", [{
        id: 4,
        int_array: [],
        string_array: [],
        nested_array: [],
        nullable_array: [],
      }],)

      result = client.execute("SELECT * FROM test_arrays_integration WHERE id = 4").first
      expect(result["int_array"]).to eq([])
      expect(result["string_array"]).to eq([])
      expect(result["nested_array"]).to eq([])
      expect(result["nullable_array"]).to eq([])
    end
  end

  describe "tuple types" do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_tuples_integration (
          id UInt64,
          simple_tuple Tuple(String, Int32),
          nested_tuple Tuple(String, Tuple(Int32, Int32)),
          array_tuple Array(Tuple(String, Int32))
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute("DROP TABLE IF EXISTS test_tuples_integration")
    end

    it "correctly handles simple tuples" do
      client.insert("test_tuples_integration", [{
        id: 1,
        simple_tuple: ["hello", 42],
        nested_tuple: ["outer", [1, 2]],
        array_tuple: [["a", 1], ["b", 2]],
      }],)

      result = client.execute("SELECT simple_tuple FROM test_tuples_integration WHERE id = 1").first
      expect(result["simple_tuple"]).to eq(["hello", 42])
    end

    it "correctly handles nested tuples" do
      client.insert("test_tuples_integration", [{
        id: 2,
        simple_tuple: ["test", 0],
        nested_tuple: ["outer", [100, 200]],
        array_tuple: [],
      }],)

      result = client.execute("SELECT nested_tuple FROM test_tuples_integration WHERE id = 2").first
      expect(result["nested_tuple"]).to eq(["outer", [100, 200]])
    end

    # CRITICAL: This tests the fix for issue #210
    it "correctly handles Array(Tuple(String, Int32))" do
      client.insert("test_tuples_integration", [{
        id: 3,
        simple_tuple: ["", 0],
        nested_tuple: ["", [0, 0]],
        array_tuple: [["first", 1], ["second", 2], ["third", 3]],
      }],)

      result = client.execute("SELECT array_tuple FROM test_tuples_integration WHERE id = 3").first
      expect(result["array_tuple"]).to eq([["first", 1], ["second", 2], ["third", 3]])
    end
  end

  describe "map types" do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_maps_integration (
          id UInt64,
          simple_map Map(String, Int32),
          nested_map Map(String, Array(Int32)),
          string_map Map(String, String)
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute("DROP TABLE IF EXISTS test_maps_integration")
    end

    it "correctly handles simple maps" do
      client.insert("test_maps_integration", [{
        id: 1,
        simple_map: { "a" => 1, "b" => 2, "c" => 3 },
        nested_map: {},
        string_map: {},
      }],)

      result = client.execute("SELECT simple_map FROM test_maps_integration WHERE id = 1").first
      expect(result["simple_map"]).to eq({ "a" => 1, "b" => 2, "c" => 3 })
    end

    it "correctly handles nested maps with arrays" do
      client.insert("test_maps_integration", [{
        id: 2,
        simple_map: {},
        nested_map: { "x" => [1, 2, 3], "y" => [4, 5, 6] },
        string_map: {},
      }],)

      result = client.execute("SELECT nested_map FROM test_maps_integration WHERE id = 2").first
      expect(result["nested_map"]).to eq({ "x" => [1, 2, 3], "y" => [4, 5, 6] })
    end

    it "correctly handles empty maps" do
      client.insert("test_maps_integration", [{
        id: 3,
        simple_map: {},
        nested_map: {},
        string_map: {},
      }],)

      result = client.execute("SELECT * FROM test_maps_integration WHERE id = 3").first
      expect(result["simple_map"]).to eq({})
      expect(result["nested_map"]).to eq({})
    end
  end

  describe "nullable types" do
    # NOTE: ClickHouse does not allow Nullable(Array(...)) - arrays cannot be nullable.
    # Use Array(Nullable(...)) if you need nullable elements inside an array.
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_nullable_integration (
          id UInt64,
          nullable_int Nullable(Int32),
          nullable_string Nullable(String),
          nullable_elements Array(Nullable(Int32))
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute("DROP TABLE IF EXISTS test_nullable_integration")
    end

    it "correctly handles null values" do
      client.insert("test_nullable_integration", [{
        id: 1,
        nullable_int: nil,
        nullable_string: nil,
        nullable_elements: [],
      }],)

      result = client.execute("SELECT * FROM test_nullable_integration WHERE id = 1").first
      expect(result["nullable_int"]).to be_nil
      expect(result["nullable_string"]).to be_nil
      expect(result["nullable_elements"]).to eq([])
    end

    it "correctly handles non-null values in nullable columns" do
      client.insert("test_nullable_integration", [{
        id: 2,
        nullable_int: 42,
        nullable_string: "hello",
        nullable_elements: [1, nil, 3], # Array with nullable elements
      }],)

      result = client.execute("SELECT * FROM test_nullable_integration WHERE id = 2").first
      expect(result["nullable_int"]).to eq(42)
      expect(result["nullable_string"]).to eq("hello")
      expect(result["nullable_elements"]).to eq([1, nil, 3])
    end
  end

  describe "deeply nested complex types" do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_complex_integration (
          id UInt64,
          deep_map Map(String, Array(Tuple(String, Nullable(Int64)))),
          complex_array Array(Map(String, Int32))
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute("DROP TABLE IF EXISTS test_complex_integration")
    end

    # CRITICAL: This tests deeply nested type handling
    it "correctly handles Map(String, Array(Tuple(String, Nullable(Int64))))" do
      data = {
        "key1" => [["a", 1], ["b", nil]],
        "key2" => [["c", 3], ["d", 4]],
      }

      client.insert("test_complex_integration", [{
        id: 1,
        deep_map: data,
        complex_array: [],
      }],)

      result = client.execute("SELECT deep_map FROM test_complex_integration WHERE id = 1").first
      expect(result["deep_map"]["key1"]).to eq([["a", 1], ["b", nil]])
      expect(result["deep_map"]["key2"]).to eq([["c", 3], ["d", 4]])
    end

    it "correctly handles Array(Map(String, Int32))" do
      data = [
        { "a" => 1, "b" => 2 },
        { "c" => 3, "d" => 4 },
      ]

      client.insert("test_complex_integration", [{
        id: 2,
        deep_map: {},
        complex_array: data,
      }],)

      result = client.execute("SELECT complex_array FROM test_complex_integration WHERE id = 2").first
      expect(result["complex_array"]).to eq(data)
    end
  end

  describe "Enum types" do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_enum_integration (
          id UInt64,
          status Enum8('active' = 1, 'inactive' = 2, 'pending' = 3),
          level Enum16('low' = 100, 'medium' = 200, 'high' = 300),
          simple_enum Enum('a', 'b', 'c')
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute("DROP TABLE IF EXISTS test_enum_integration")
    end

    it "correctly handles Enum round-trip INSERT/SELECT" do
      client.insert("test_enum_integration", [{
        id: 1,
        status: "active",
        level: "high",
        simple_enum: "a",
      }],)

      result = client.execute("SELECT * FROM test_enum_integration WHERE id = 1").first

      expect(result["id"]).to eq(1)
      expect(result["status"]).to eq("active")
      expect(result["level"]).to eq("high")
      expect(result["simple_enum"]).to eq("a")
    end

    it "correctly handles Enum8 type with multiple values" do
      client.insert("test_enum_integration", [{
        id: 2,
        status: "inactive",
        level: "low",
        simple_enum: "b",
      }],)

      result = client.execute("SELECT * FROM test_enum_integration WHERE id = 2").first

      expect(result["status"]).to eq("inactive")
      expect(result["level"]).to eq("low")
      expect(result["simple_enum"]).to eq("b")
    end

    it "correctly handles Enum16 with large numeric values" do
      client.insert("test_enum_integration", [{
        id: 3,
        status: "pending",
        level: "medium",
        simple_enum: "c",
      }],)

      result = client.execute("SELECT * FROM test_enum_integration WHERE id = 3").first

      expect(result["status"]).to eq("pending")
      expect(result["level"]).to eq("medium")
      expect(result["simple_enum"]).to eq("c")
    end
  end

  describe "Decimal types" do
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_decimal_integration (
          id UInt64,
          decimal_val Decimal(18, 4),
          decimal32_val Decimal32(2),
          decimal64_val Decimal64(8),
          decimal128_val Decimal128(18)
        ) ENGINE = MergeTree() ORDER BY id
      SQL
    end

    after do
      client.execute("DROP TABLE IF EXISTS test_decimal_integration")
    end

    it "correctly handles Decimal(18, 4) round-trip" do
      client.insert("test_decimal_integration", [{
        id: 1,
        decimal_val: BigDecimal("123.4567"),
        decimal32_val: BigDecimal("99.99"),
        decimal64_val: BigDecimal("123456789.12345678"),
        decimal128_val: BigDecimal("123456789012345678.123456789012345678"),
      }],)

      result = client.execute("SELECT * FROM test_decimal_integration WHERE id = 1").first

      expect(result["decimal_val"]).to be_a(BigDecimal)
      expect(result["decimal_val"]).to eq(BigDecimal("123.4567"))
      expect(result["decimal32_val"]).to be_a(BigDecimal)
      expect(result["decimal64_val"]).to be_a(BigDecimal)
      expect(result["decimal128_val"]).to be_a(BigDecimal)
    end

    it "correctly handles negative Decimal values" do
      client.insert("test_decimal_integration", [{
        id: 2,
        decimal_val: BigDecimal("-999.1234"),
        decimal32_val: BigDecimal("-50.25"),
        decimal64_val: BigDecimal("-12345.6789"),
        decimal128_val: BigDecimal("-999999999999.999999999999999999"),
      }],)

      result = client.execute("SELECT * FROM test_decimal_integration WHERE id = 2").first

      expect(result["decimal_val"]).to eq(BigDecimal("-999.1234"))
      expect(result["decimal32_val"]).to eq(BigDecimal("-50.25"))
    end

    it "correctly handles zero and small values" do
      client.insert("test_decimal_integration", [{
        id: 3,
        decimal_val: BigDecimal("0.0001"),
        decimal32_val: BigDecimal("0.01"),
        decimal64_val: BigDecimal("0"),
        decimal128_val: BigDecimal("0.000000000000000001"),
      }],)

      result = client.execute("SELECT * FROM test_decimal_integration WHERE id = 3").first

      expect(result["decimal_val"]).to eq(BigDecimal("0.0001"))
      expect(result["decimal32_val"]).to eq(BigDecimal("0.01"))
      expect(result["decimal64_val"]).to eq(BigDecimal("0"))
    end
  end

  describe "type introspection from query results" do
    it "correctly determines types from SELECT results" do
      result = client.execute(<<~SQL)
        SELECT
          toInt32(42) as int_val,
          'hello' as string_val,
          [1, 2, 3] as array_val,
          (1, 'a') as tuple_val,
          map('key', 1) as map_val
      SQL

      row = result.first

      expect(row["int_val"]).to be_a(Integer)
      expect(row["string_val"]).to be_a(String)
      expect(row["array_val"]).to be_an(Array)
      # Tuple and Map results depend on response format
    end
  end
end
