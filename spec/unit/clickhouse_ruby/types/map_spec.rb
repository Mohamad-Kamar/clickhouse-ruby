# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Types::Map do
  describe "#initialize" do
    it "accepts key and value types" do
      key_type = ClickhouseRuby::Types::Base.new("String")
      value_type = ClickhouseRuby::Types::Integer.new("Int32")
      type = described_class.new("Map", arg_types: [key_type, value_type])

      expect(type.key_type).to eq(key_type)
      expect(type.value_type).to eq(value_type)
    end

    it "defaults to String key and value types" do
      type = described_class.new("Map")
      expect(type.key_type.name).to eq("String")
      expect(type.value_type.name).to eq("String")
    end
  end

  describe "#to_s" do
    it "returns the full type string" do
      key_type = ClickhouseRuby::Types::Base.new("String")
      value_type = ClickhouseRuby::Types::Integer.new("Int32")
      type = described_class.new("Map", arg_types: [key_type, value_type])
      expect(type.to_s).to eq("Map(String, Int32)")
    end
  end

  describe "#cast" do
    context "with String keys and Int32 values" do
      subject(:type) do
        key_type = ClickhouseRuby::Types::Base.new("String")
        value_type = ClickhouseRuby::Types::Integer.new("Int32")
        described_class.new("Map", arg_types: [key_type, value_type])
      end

      it "casts hashes" do
        expect(type.cast({ "a" => 1, "b" => 2 })).to eq({ "a" => 1, "b" => 2 })
      end

      it "casts string values to integers" do
        expect(type.cast({ "a" => "1", "b" => "2" })).to eq({ "a" => 1, "b" => 2 })
      end

      it "returns empty hash for empty input" do
        expect(type.cast({})).to eq({})
      end

      it "returns nil for nil input" do
        expect(type.cast(nil)).to be_nil
      end
    end

    context "from string representation" do
      subject(:type) do
        key_type = ClickhouseRuby::Types::Base.new("String")
        value_type = ClickhouseRuby::Types::Integer.new("Int32")
        described_class.new("Map", arg_types: [key_type, value_type])
      end

      it "parses map string format" do
        expect(type.cast("{'a': 1, 'b': 2}")).to eq({ "a" => 1, "b" => 2 })
      end

      it "parses empty map string" do
        expect(type.cast("{}")).to eq({})
      end

      it "raises TypeCastError for invalid format" do
        expect { type.cast("not a map") }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context "from unsupported types" do
      subject(:type) { described_class.new("Map") }

      it "raises TypeCastError for arrays" do
        expect { type.cast([1, 2, 3]) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises TypeCastError for integers" do
        expect { type.cast(42) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end
  end

  describe "#deserialize" do
    subject(:type) do
      key_type = ClickhouseRuby::Types::Base.new("String")
      value_type = ClickhouseRuby::Types::Integer.new("Int32")
      described_class.new("Map", arg_types: [key_type, value_type])
    end

    it "deserializes hashes" do
      expect(type.deserialize({ "a" => 1 })).to eq({ "a" => 1 })
    end

    it "deserializes string representations" do
      expect(type.deserialize("{'a': 1}")).to eq({ "a" => 1 })
    end

    it "returns nil for nil" do
      expect(type.deserialize(nil)).to be_nil
    end
  end

  describe "#serialize" do
    subject(:type) do
      key_type = ClickhouseRuby::Types::Base.new("String")
      value_type = ClickhouseRuby::Types::Integer.new("Int32")
      described_class.new("Map", arg_types: [key_type, value_type])
    end

    it "serializes hashes to SQL format" do
      expect(type.serialize({ "a" => 1, "b" => 2 })).to eq("{a: 1, b: 2}")
    end

    it "serializes empty hashes" do
      expect(type.serialize({})).to eq("{}")
    end

    it "returns NULL for nil" do
      expect(type.serialize(nil)).to eq("NULL")
    end
  end

  describe "nested map types" do
    context "Map(String, Array(Int32))" do
      subject(:type) do
        key_type = ClickhouseRuby::Types::Base.new("String")
        array_type = ClickhouseRuby::Types::Array.new("Array", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
        described_class.new("Map", arg_types: [key_type, array_type])
      end

      it "casts maps with array values" do
        input = { "a" => [1, 2], "b" => [3, 4] }
        expect(type.cast(input)).to eq(input)
      end

      it "returns the correct type string" do
        expect(type.to_s).to eq("Map(String, Array(Int32))")
      end
    end

    context "Map(String, Nullable(Int32))" do
      subject(:type) do
        key_type = ClickhouseRuby::Types::Base.new("String")
        nullable_int = ClickhouseRuby::Types::Nullable.new("Nullable", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
        described_class.new("Map", arg_types: [key_type, nullable_int])
      end

      it "casts maps with nullable values" do
        expect(type.cast({ "a" => 1, "b" => nil })).to eq({ "a" => 1, "b" => nil })
      end

      it "serializes maps with null values" do
        expect(type.serialize({ "a" => 1, "b" => nil })).to eq("{a: 1, b: NULL}")
      end
    end
  end

  describe "string parsing edge cases" do
    subject(:type) do
      key_type = ClickhouseRuby::Types::Base.new("String")
      value_type = ClickhouseRuby::Types::Base.new("String")
      described_class.new("Map", arg_types: [key_type, value_type])
    end

    it "handles keys with special characters" do
      expect(type.cast("{'key:with:colons': 'value'}")).to eq({ "key:with:colons" => "value" })
    end

    it "handles values with commas" do
      expect(type.cast("{'key': 'value, with, commas'}")).to eq({ "key" => "value, with, commas" })
    end

    it "handles escaped quotes" do
      expect(type.cast("{'key': 'it\\'s ok'}")).to eq({ "key" => "it's ok" })
    end
  end
end
