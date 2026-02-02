# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Types::Decimal do
  describe "Decimal(18, 4)" do
    subject(:type) { described_class.new("Decimal(18, 4)") }

    it "parses precision and scale" do
      expect(type.precision).to eq(18)
      expect(type.scale).to eq(4)
    end

    it "determines internal type" do
      expect(type.internal_type).to eq(:Decimal64)
    end
  end

  describe "Decimal64(4)" do
    subject(:type) { described_class.new("Decimal64(4)") }

    it "uses max precision for variant" do
      expect(type.precision).to eq(18)
      expect(type.scale).to eq(4)
    end

    it "determines internal type" do
      expect(type.internal_type).to eq(:Decimal64)
    end
  end

  describe "Decimal32(2)" do
    subject(:type) { described_class.new("Decimal32(2)") }

    it "uses max precision for Decimal32" do
      expect(type.precision).to eq(9)
      expect(type.scale).to eq(2)
    end

    it "determines internal type" do
      expect(type.internal_type).to eq(:Decimal32)
    end
  end

  describe "Decimal128(10)" do
    subject(:type) { described_class.new("Decimal128(10)") }

    it "uses max precision for Decimal128" do
      expect(type.precision).to eq(38)
      expect(type.scale).to eq(10)
    end

    it "determines internal type" do
      expect(type.internal_type).to eq(:Decimal128)
    end
  end

  describe "Decimal256(20)" do
    subject(:type) { described_class.new("Decimal256(20)") }

    it "uses max precision for Decimal256" do
      expect(type.precision).to eq(76)
      expect(type.scale).to eq(20)
    end

    it "determines internal type" do
      expect(type.internal_type).to eq(:Decimal256)
    end
  end

  describe "#cast" do
    subject(:type) { described_class.new("Decimal(10, 2)") }

    context "from Integer" do
      it "converts integer" do
        expect(type.cast(42)).to eq(BigDecimal("42"))
      end

      it "converts negative integer" do
        expect(type.cast(-42)).to eq(BigDecimal("-42"))
      end

      it "converts zero" do
        expect(type.cast(0)).to eq(BigDecimal("0"))
      end
    end

    context "from Float" do
      it "converts float" do
        result = type.cast(42.5)
        expect(result).to be_a(BigDecimal)
        expect(result.to_f).to be_within(0.01).of(42.5)
      end

      it "converts negative float" do
        result = type.cast(-42.5)
        expect(result).to be_a(BigDecimal)
        expect(result.to_f).to be_within(0.01).of(-42.5)
      end
    end

    context "from String" do
      it "converts string preserving precision" do
        result = type.cast("123.456789")
        expect(result).to eq(BigDecimal("123.456789"))
      end

      it "converts negative string" do
        result = type.cast("-123.45")
        expect(result).to eq(BigDecimal("-123.45"))
      end

      it "converts string with leading zeros" do
        result = type.cast("00123.45")
        expect(result).to eq(BigDecimal("123.45"))
      end
    end

    context "from BigDecimal" do
      it "returns the bigdecimal unchanged" do
        bd = BigDecimal("123.45")
        expect(type.cast(bd)).to eq(bd)
      end
    end

    context "from nil" do
      it "returns nil" do
        expect(type.cast(nil)).to be_nil
      end
    end

    context "precision overflow" do
      it "raises on integer part exceeding max digits" do
        # Decimal(10, 2) allows max 8 integer digits
        expect { type.cast("123456789.00") }
          .to raise_error(ClickhouseRuby::TypeCastError, /exceeds maximum integer digits/)
      end

      it "raises on negative integer part exceeding max digits" do
        expect { type.cast("-123456789.00") }
          .to raise_error(ClickhouseRuby::TypeCastError, /exceeds maximum integer digits/)
      end

      it "accepts value at precision limit" do
        # 8 integer digits, 2 fractional = 99999999.99
        result = type.cast("99999999.99")
        expect(result).to eq(BigDecimal("99999999.99"))
      end
    end

    context "unsupported types" do
      it "raises TypeCastError for arrays" do
        expect { type.cast([1, 2, 3]) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises TypeCastError for hashes" do
        expect { type.cast({ a: 1 }) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises TypeCastError for symbols" do
        expect { type.cast(:symbol) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end
  end

  describe "#deserialize" do
    subject(:type) { described_class.new("Decimal(10, 2)") }

    it "converts string value from ClickHouse" do
      result = type.deserialize("123.45")
      expect(result).to eq(BigDecimal("123.45"))
    end

    it "converts integer value from ClickHouse" do
      result = type.deserialize(123)
      expect(result).to eq(BigDecimal("123"))
    end

    it "returns nil for nil" do
      expect(type.deserialize(nil)).to be_nil
    end

    it "preserves high precision strings" do
      result = type.deserialize("123.456789012345678901234567890")
      expect(result).to eq(BigDecimal("123.456789012345678901234567890"))
    end
  end

  describe "#serialize" do
    subject(:type) { described_class.new("Decimal(38, 18)") }

    it "preserves high precision" do
      value = BigDecimal("123.456789012345678901234567")
      serialized = type.serialize(value)
      expect(serialized).to start_with("123.456789012345678")
    end

    it "converts integer to string" do
      value = BigDecimal("42")
      serialized = type.serialize(value)
      expect(serialized).to match(/^42/)
    end

    it "returns NULL for nil" do
      expect(type.serialize(nil)).to eq("NULL")
    end

    it "uses F format for precision" do
      value = BigDecimal("123.45")
      serialized = type.serialize(value)
      # F format returns fixed-point notation, not scientific
      expect(serialized).not_to include("E")
    end
  end

  describe "validation" do
    context "precision validation" do
      it "raises for precision below 1" do
        expect { described_class.new("Decimal(0, 0)") }
          .to raise_error(ClickhouseRuby::ConfigurationError, /precision must be 1-76/)
      end

      it "raises for precision above 76" do
        expect { described_class.new("Decimal(77, 10)") }
          .to raise_error(ClickhouseRuby::ConfigurationError, /precision must be 1-76/)
      end

      it "accepts precision at minimum (1)" do
        type = described_class.new("Decimal(1, 0)")
        expect(type.precision).to eq(1)
      end

      it "accepts precision at maximum (76)" do
        type = described_class.new("Decimal(76, 10)")
        expect(type.precision).to eq(76)
      end
    end

    context "scale validation" do
      it "raises when scale exceeds precision" do
        expect { described_class.new("Decimal(5, 10)") }
          .to raise_error(ClickhouseRuby::ConfigurationError, /scale must be 0-/)
      end

      it "raises when scale is negative" do
        expect { described_class.new("Decimal(10, -1)") }
          .to raise_error(ClickhouseRuby::ConfigurationError, /scale must be 0-/)
      end

      it "accepts scale equal to precision" do
        type = described_class.new("Decimal(5, 5)")
        expect(type.scale).to eq(5)
      end

      it "accepts scale of 0" do
        type = described_class.new("Decimal(10, 0)")
        expect(type.scale).to eq(0)
      end
    end
  end

  describe "internal type determination" do
    it "returns Decimal32 for precision 1-9" do
      expect(described_class.new("Decimal(5, 2)").internal_type).to eq(:Decimal32)
      expect(described_class.new("Decimal(9, 2)").internal_type).to eq(:Decimal32)
    end

    it "returns Decimal64 for precision 10-18" do
      expect(described_class.new("Decimal(10, 2)").internal_type).to eq(:Decimal64)
      expect(described_class.new("Decimal(18, 2)").internal_type).to eq(:Decimal64)
    end

    it "returns Decimal128 for precision 19-38" do
      expect(described_class.new("Decimal(19, 2)").internal_type).to eq(:Decimal128)
      expect(described_class.new("Decimal(38, 2)").internal_type).to eq(:Decimal128)
    end

    it "returns Decimal256 for precision 39-76" do
      expect(described_class.new("Decimal(39, 2)").internal_type).to eq(:Decimal256)
      expect(described_class.new("Decimal(76, 2)").internal_type).to eq(:Decimal256)
    end
  end

  describe "edge cases" do
    context "zero scale behavior" do
      subject(:type) { described_class.new("Decimal(10, 0)") }

      it "accepts integer values" do
        expect(type.cast(123)).to eq(BigDecimal("123"))
      end

      it "serializes without decimal point" do
        serialized = type.serialize(BigDecimal("123"))
        expect(serialized).to match(/^123/)
      end
    end

    context "very high precision" do
      subject(:type) { described_class.new("Decimal(76, 50)") }

      it "handles high precision strings" do
        value = "1.#{"1" * 50}"
        result = type.cast(value)
        expect(result).to eq(BigDecimal(value))
      end
    end

    context "negative values" do
      subject(:type) { described_class.new("Decimal(18, 4)") }

      it "casts negative values" do
        result = type.cast("-123.45")
        expect(result).to eq(BigDecimal("-123.45"))
      end

      it "serializes negative values" do
        serialized = type.serialize(BigDecimal("-123.45"))
        expect(serialized).to include("-")
      end
    end
  end

  describe "type class structure" do
    subject(:type) { described_class.new("Decimal(18, 4)") }

    it "has name attribute" do
      expect(type.name).to eq("Decimal(18, 4)")
    end

    it "responds to precision" do
      expect(type).to respond_to(:precision)
    end

    it "responds to scale" do
      expect(type).to respond_to(:scale)
    end

    it "responds to internal_type" do
      expect(type).to respond_to(:internal_type)
    end

    it "responds to cast" do
      expect(type).to respond_to(:cast)
    end

    it "responds to deserialize" do
      expect(type).to respond_to(:deserialize)
    end

    it "responds to serialize" do
      expect(type).to respond_to(:serialize)
    end
  end
end
