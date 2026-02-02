# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Types::LowCardinality do
  describe "with String element type" do
    subject(:type) { described_class.new("LowCardinality(String)", element_type: string_type) }

    let(:string_type) { ClickhouseRuby::Types::String.new("String") }

    describe "#name" do
      it "returns LowCardinality(String)" do
        expect(type.name).to eq("LowCardinality(String)")
      end
    end

    describe "#element_type" do
      it "returns the wrapped type" do
        expect(type.element_type).to eq(string_type)
      end
    end

    describe "#to_s" do
      it "returns the full type string" do
        expect(type.to_s).to eq("LowCardinality(String)")
      end
    end

    describe "#cast" do
      it "delegates to element type" do
        expect(type.cast("hello")).to eq("hello")
      end

      it "handles nil" do
        expect(type.cast(nil)).to be_nil
      end

      it "converts other types to string" do
        expect(type.cast(42)).to eq("42")
      end
    end

    describe "#deserialize" do
      it "delegates to element type" do
        expect(type.deserialize("hello")).to eq("hello")
      end

      it "handles nil" do
        expect(type.deserialize(nil)).to be_nil
      end
    end

    describe "#serialize" do
      it "delegates to element type" do
        expect(type.serialize("hello")).to eq("'hello'")
      end

      it "returns NULL for nil" do
        expect(type.serialize(nil)).to eq("NULL")
      end
    end
  end

  describe "with Integer element type" do
    subject(:type) { described_class.new("LowCardinality(UInt32)", element_type: int_type) }

    let(:int_type) { ClickhouseRuby::Types::Integer.new("UInt32") }

    describe "#cast" do
      it "delegates to element type" do
        expect(type.cast(42)).to eq(42)
      end

      it "converts strings to integers" do
        expect(type.cast("42")).to eq(42)
      end
    end

    describe "#deserialize" do
      it "delegates to element type" do
        expect(type.deserialize(42)).to eq(42)
        expect(type.deserialize("42")).to eq(42)
      end
    end

    describe "#serialize" do
      it "delegates to element type" do
        expect(type.serialize(42)).to eq("42")
      end
    end
  end

  describe "with FixedString element type" do
    subject(:type) { described_class.new("LowCardinality(FixedString(5))", element_type: fixed_type) }

    let(:fixed_type) { ClickhouseRuby::Types::String.new("FixedString(5)", length: 5) }

    describe "#cast" do
      it "pads short strings" do
        result = type.cast("hi")
        expect(result.length).to eq(5)
      end

      it "truncates long strings" do
        result = type.cast("hello world")
        expect(result.length).to eq(5)
      end
    end

    describe "#deserialize" do
      it "removes null padding" do
        expect(type.deserialize("hi\0\0\0")).to eq("hi")
      end
    end
  end

  describe "with Nullable element type" do
    subject(:type) { described_class.new("LowCardinality(Nullable(String))", element_type: nullable_type) }

    let(:nullable_type) { ClickhouseRuby::Types::Nullable.new("Nullable(String)", element_type: ClickhouseRuby::Types::String.new("String")) }

    describe "#cast" do
      it "handles nil" do
        expect(type.cast(nil)).to be_nil
      end

      it "handles values" do
        expect(type.cast("hello")).to eq("hello")
      end
    end
  end

  describe "default element type" do
    subject(:type) { described_class.new("LowCardinality(String)") }

    it "defaults to Base type" do
      expect(type.element_type).to be_a(ClickhouseRuby::Types::Base)
    end
  end

  describe "pass-through behavior" do
    subject(:type) { described_class.new("LowCardinality(String)", element_type: string_type) }

    let(:string_type) { ClickhouseRuby::Types::String.new("String") }

    it "is transparent for cast operations" do
      value = "test value"
      expect(type.cast(value)).to eq(string_type.cast(value))
    end

    it "is transparent for deserialize operations" do
      value = "test value"
      expect(type.deserialize(value)).to eq(string_type.deserialize(value))
    end

    it "is transparent for serialize operations" do
      value = "test value"
      expect(type.serialize(value)).to eq(string_type.serialize(value))
    end
  end
end
