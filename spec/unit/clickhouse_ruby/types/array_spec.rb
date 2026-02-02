# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Types::Array do
  describe "#initialize" do
    it "accepts an element type" do
      element_type = ClickhouseRuby::Types::Integer.new("Int32")
      type = described_class.new("Array", element_type: element_type)
      expect(type.element_type).to eq(element_type)
    end

    it "defaults to String element type" do
      type = described_class.new("Array")
      expect(type.element_type.name).to eq("String")
    end
  end

  describe "#to_s" do
    it "returns the full type string" do
      element_type = ClickhouseRuby::Types::Integer.new("Int32")
      type = described_class.new("Array", element_type: element_type)
      expect(type.to_s).to eq("Array(Int32)")
    end
  end

  describe "#cast" do
    context "with integer element type" do
      subject(:type) do
        described_class.new("Array", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
      end

      it "casts arrays of integers" do
        expect(type.cast([1, 2, 3])).to eq([1, 2, 3])
      end

      it "casts arrays of strings to integers" do
        expect(type.cast(%w[1 2 3])).to eq([1, 2, 3])
      end

      it "casts mixed arrays" do
        expect(type.cast([1, "2", 3.0])).to eq([1, 2, 3])
      end

      it "returns empty array for empty input" do
        expect(type.cast([])).to eq([])
      end

      it "returns nil for nil input" do
        expect(type.cast(nil)).to be_nil
      end
    end

    context "with string element type" do
      subject(:type) do
        described_class.new("Array", element_type: ClickhouseRuby::Types::Base.new("String"))
      end

      it "casts arrays of strings" do
        expect(type.cast(%w[a b c])).to eq(%w[a b c])
      end
    end

    context "from string representation" do
      subject(:type) do
        described_class.new("Array", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
      end

      it "parses array string format" do
        expect(type.cast("[1, 2, 3]")).to eq([1, 2, 3])
      end

      it "parses empty array string" do
        expect(type.cast("[]")).to eq([])
      end

      it "handles quoted string elements" do
        string_type = described_class.new("Array", element_type: ClickhouseRuby::Types::Base.new("String"))
        expect(string_type.cast("['a', 'b', 'c']")).to eq(%w[a b c])
      end

      it "raises TypeCastError for invalid format" do
        expect { type.cast("not an array") }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context "from unsupported types" do
      subject(:type) do
        described_class.new("Array", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
      end

      it "raises TypeCastError for non-array values" do
        expect { type.cast(42) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises TypeCastError for hashes" do
        expect { type.cast({ a: 1 }) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end
  end

  describe "#deserialize" do
    subject(:type) do
      described_class.new("Array", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
    end

    it "deserializes arrays" do
      expect(type.deserialize([1, 2, 3])).to eq([1, 2, 3])
    end

    it "deserializes string representations" do
      expect(type.deserialize("[1, 2, 3]")).to eq([1, 2, 3])
    end

    it "returns nil for nil" do
      expect(type.deserialize(nil)).to be_nil
    end

    it "wraps non-array values in array" do
      expect(type.deserialize(42)).to eq([42])
    end
  end

  describe "#serialize" do
    subject(:type) do
      described_class.new("Array", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
    end

    it "serializes arrays to SQL format" do
      expect(type.serialize([1, 2, 3])).to eq("[1, 2, 3]")
    end

    it "serializes empty arrays" do
      expect(type.serialize([])).to eq("[]")
    end

    it "returns NULL for nil" do
      expect(type.serialize(nil)).to eq("NULL")
    end

    context "with string element type" do
      subject(:type) do
        # Using Base type which just does to_s
        described_class.new("Array", element_type: ClickhouseRuby::Types::Base.new("String"))
      end

      it "serializes string arrays" do
        expect(type.serialize(%w[a b c])).to eq("[a, b, c]")
      end
    end
  end

  describe "nested arrays" do
    context "Array(Array(Int32))" do
      subject(:type) do
        inner_type = described_class.new("Array", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
        described_class.new("Array", element_type: inner_type)
      end

      it "casts nested arrays" do
        input = [[1, 2], [3, 4], [5, 6]]
        expect(type.cast(input)).to eq([[1, 2], [3, 4], [5, 6]])
      end

      it "returns the correct type string" do
        expect(type.to_s).to eq("Array(Array(Int32))")
      end

      it "serializes nested arrays" do
        expect(type.serialize([[1, 2], [3, 4]])).to eq("[[1, 2], [3, 4]]")
      end

      it "handles empty nested arrays" do
        expect(type.cast([[], [1], []])).to eq([[], [1], []])
      end
    end

    context "deeply nested arrays" do
      subject(:type) do
        level1 = ClickhouseRuby::Types::Integer.new("Int32")
        level2 = described_class.new("Array", element_type: level1)
        level3 = described_class.new("Array", element_type: level2)
        described_class.new("Array", element_type: level3)
      end

      it "casts 3-level nested arrays" do
        input = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
        expect(type.cast(input)).to eq([[[1, 2], [3, 4]], [[5, 6], [7, 8]]])
      end

      it "returns the correct type string" do
        expect(type.to_s).to eq("Array(Array(Array(Int32)))")
      end
    end
  end

  describe "arrays with nullable elements" do
    subject(:type) do
      nullable_int = ClickhouseRuby::Types::Nullable.new("Nullable", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
      described_class.new("Array", element_type: nullable_int)
    end

    it "casts arrays with nil elements" do
      expect(type.cast([1, nil, 3])).to eq([1, nil, 3])
    end

    it "returns the correct type string" do
      expect(type.to_s).to eq("Array(Nullable(Int32))")
    end

    it "serializes arrays with nil elements" do
      expect(type.serialize([1, nil, 3])).to eq("[1, NULL, 3]")
    end
  end

  describe "arrays with tuple elements" do
    subject(:type) do
      string_type = ClickhouseRuby::Types::Base.new("String")
      int_type = ClickhouseRuby::Types::Integer.new("UInt64")
      tuple_type = ClickhouseRuby::Types::Tuple.new("Tuple", arg_types: [string_type, int_type])
      described_class.new("Array", element_type: tuple_type)
    end

    it "casts arrays of tuples" do
      input = [["hello", 1], ["world", 2]]
      expect(type.cast(input)).to eq([["hello", 1], ["world", 2]])
    end

    it "returns the correct type string" do
      expect(type.to_s).to eq("Array(Tuple(String, UInt64))")
    end

    it "serializes arrays of tuples" do
      expect(type.serialize([["hello", 1], ["world", 2]])).to eq("[(hello, 1), (world, 2)]")
    end
  end

  describe "string parsing edge cases" do
    subject(:type) do
      described_class.new("Array", element_type: ClickhouseRuby::Types::Base.new("String"))
    end

    it "handles strings with escaped quotes" do
      expect(type.cast("['it\\'s', 'ok']")).to eq(["it's", "ok"])
    end

    it "handles strings with commas" do
      expect(type.cast("['a, b', 'c']")).to eq(["a, b", "c"])
    end

    it "handles strings with brackets" do
      expect(type.cast("['[test]', 'ok']")).to eq(["[test]", "ok"])
    end

    it "handles nested array strings" do
      nested_type = described_class.new("Array", element_type: type)
      result = nested_type.deserialize("[['a', 'b'], ['c', 'd']]")
      expect(result).to eq([%w[a b], %w[c d]])
    end
  end
end
