# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Types::Nullable do
  describe "#initialize" do
    it "accepts an element type" do
      element_type = ClickhouseRuby::Types::Integer.new("Int32")
      type = described_class.new("Nullable", element_type: element_type)
      expect(type.element_type).to eq(element_type)
    end

    it "defaults to String element type" do
      type = described_class.new("Nullable")
      expect(type.element_type.name).to eq("String")
    end
  end

  describe "#nullable?" do
    it "returns true" do
      type = described_class.new("Nullable")
      expect(type.nullable?).to be true
    end
  end

  describe "#to_s" do
    it "returns the full type string" do
      element_type = ClickhouseRuby::Types::Integer.new("Int32")
      type = described_class.new("Nullable", element_type: element_type)
      expect(type.to_s).to eq("Nullable(Int32)")
    end
  end

  describe "#cast" do
    context "with integer element type" do
      subject(:type) do
        described_class.new("Nullable", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
      end

      it "returns nil for nil input" do
        expect(type.cast(nil)).to be_nil
      end

      it "casts non-nil values through element type" do
        expect(type.cast(42)).to eq(42)
      end

      it "casts strings to integers" do
        expect(type.cast("42")).to eq(42)
      end
    end

    context "with string element type" do
      subject(:type) do
        described_class.new("Nullable", element_type: ClickhouseRuby::Types::Base.new("String"))
      end

      it "returns nil for nil input" do
        expect(type.cast(nil)).to be_nil
      end

      it "casts strings" do
        expect(type.cast("hello")).to eq("hello")
      end
    end
  end

  describe "#deserialize" do
    subject(:type) do
      described_class.new("Nullable", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
    end

    it "returns nil for nil input" do
      expect(type.deserialize(nil)).to be_nil
    end

    it "returns nil for ClickHouse NULL representation" do
      expect(type.deserialize('\\N')).to be_nil
    end

    it "deserializes non-nil values through element type" do
      expect(type.deserialize("42")).to eq(42)
    end

    it "deserializes integer values" do
      expect(type.deserialize(42)).to eq(42)
    end
  end

  describe "#serialize" do
    subject(:type) do
      described_class.new("Nullable", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
    end

    it "returns NULL for nil input" do
      expect(type.serialize(nil)).to eq("NULL")
    end

    it "serializes non-nil values through element type" do
      expect(type.serialize(42)).to eq("42")
    end
  end

  describe "nested nullable types" do
    context "Nullable(Array(Int32))" do
      subject(:type) do
        array_type = ClickhouseRuby::Types::Array.new("Array", element_type: ClickhouseRuby::Types::Integer.new("Int32"))
        described_class.new("Nullable", element_type: array_type)
      end

      it "returns nil for nil input" do
        expect(type.cast(nil)).to be_nil
      end

      it "casts arrays" do
        expect(type.cast([1, 2, 3])).to eq([1, 2, 3])
      end

      it "returns the correct type string" do
        expect(type.to_s).to eq("Nullable(Array(Int32))")
      end
    end
  end
end
