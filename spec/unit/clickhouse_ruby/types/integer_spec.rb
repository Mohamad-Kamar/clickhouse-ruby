# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Types::Integer do
  # Test all integer type variants
  %w[Int8 Int16 Int32 Int64 UInt8 UInt16 UInt32 UInt64].each do |type_name|
    context "for #{type_name}" do
      subject(:type) { described_class.new(type_name) }

      describe "#name" do
        it "returns #{type_name}" do
          expect(type.name).to eq(type_name)
        end
      end

      describe "#unsigned?" do
        if type_name.start_with?("U")
          it "returns true" do
            expect(type.unsigned?).to be true
          end
        else
          it "returns false" do
            expect(type.unsigned?).to be false
          end
        end
      end

      describe "#bit_size" do
        expected_size = type_name.gsub(/[^0-9]/, "").to_i
        it "returns #{expected_size}" do
          expect(type.bit_size).to eq(expected_size)
        end
      end
    end
  end

  describe "#cast" do
    subject(:type) { described_class.new("Int32") }

    context "from Integer" do
      it "returns the integer unchanged" do
        expect(type.cast(42)).to eq(42)
      end

      it "returns negative integers" do
        expect(type.cast(-42)).to eq(-42)
      end

      it "returns zero" do
        expect(type.cast(0)).to eq(0)
      end
    end

    context "from Float" do
      it "truncates to integer" do
        expect(type.cast(42.7)).to eq(42)
      end

      it "truncates negative floats" do
        expect(type.cast(-42.7)).to eq(-42)
      end

      it "handles float zero" do
        expect(type.cast(0.0)).to eq(0)
      end
    end

    context "from String" do
      it "parses integer strings" do
        expect(type.cast("42")).to eq(42)
      end

      it "parses negative integer strings" do
        expect(type.cast("-42")).to eq(-42)
      end

      it "parses strings with leading/trailing whitespace" do
        expect(type.cast("  42  ")).to eq(42)
      end

      it "parses zero string" do
        expect(type.cast("0")).to eq(0)
      end

      it "raises TypeCastError for non-numeric strings" do
        expect { type.cast("hello") }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises TypeCastError for empty strings" do
        expect { type.cast("") }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises TypeCastError for float strings" do
        expect { type.cast("42.5") }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context "from Boolean" do
      it "casts true to 1" do
        expect(type.cast(true)).to eq(1)
      end

      it "casts false to 0" do
        expect(type.cast(false)).to eq(0)
      end
    end

    context "from nil" do
      it "returns nil" do
        expect(type.cast(nil)).to be_nil
      end
    end

    context "from unsupported types" do
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

    context "with TypeCastError details" do
      it "includes from_type in error" do
        expect { type.cast("hello") }.to raise_error do |error|
          expect(error.from_type).to eq("String")
        end
      end

      it "includes to_type in error" do
        expect { type.cast("hello") }.to raise_error do |error|
          expect(error.to_type).to eq("Int32")
        end
      end

      it "includes value in error" do
        expect { type.cast("hello") }.to raise_error do |error|
          expect(error.value).to eq("hello")
        end
      end
    end
  end

  describe "#cast with range validation" do
    context "for Int8 (-128 to 127)" do
      subject(:type) { described_class.new("Int8") }

      it "accepts minimum value" do
        expect(type.cast(-128)).to eq(-128)
      end

      it "accepts maximum value" do
        expect(type.cast(127)).to eq(127)
      end

      it "raises for value below minimum" do
        expect { type.cast(-129) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises for value above maximum" do
        expect { type.cast(128) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context "for UInt8 (0 to 255)" do
      subject(:type) { described_class.new("UInt8") }

      it "accepts zero" do
        expect(type.cast(0)).to eq(0)
      end

      it "accepts maximum value" do
        expect(type.cast(255)).to eq(255)
      end

      it "raises for negative values" do
        expect { type.cast(-1) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises for value above maximum" do
        expect { type.cast(256) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context "for Int64" do
      subject(:type) { described_class.new("Int64") }

      it "accepts large positive values" do
        expect(type.cast(9_223_372_036_854_775_807)).to eq(9_223_372_036_854_775_807)
      end

      it "accepts large negative values" do
        expect(type.cast(-9_223_372_036_854_775_808)).to eq(-9_223_372_036_854_775_808)
      end
    end

    context "for UInt64" do
      subject(:type) { described_class.new("UInt64") }

      it "accepts large positive values" do
        expect(type.cast(18_446_744_073_709_551_615)).to eq(18_446_744_073_709_551_615)
      end

      it "raises for negative values" do
        expect { type.cast(-1) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end
  end

  describe "#deserialize" do
    subject(:type) { described_class.new("Int32") }

    it "converts integer values" do
      expect(type.deserialize(42)).to eq(42)
    end

    it "converts string values" do
      expect(type.deserialize("42")).to eq(42)
    end

    it "converts float values" do
      expect(type.deserialize(42.0)).to eq(42)
    end

    it "returns nil for nil" do
      expect(type.deserialize(nil)).to be_nil
    end
  end

  describe "#serialize" do
    subject(:type) { described_class.new("Int32") }

    it "converts integer to string" do
      expect(type.serialize(42)).to eq("42")
    end

    it "converts negative integer to string" do
      expect(type.serialize(-42)).to eq("-42")
    end

    it "converts zero to string" do
      expect(type.serialize(0)).to eq("0")
    end

    it "returns NULL for nil" do
      expect(type.serialize(nil)).to eq("NULL")
    end
  end

  describe "large integer types (128-bit and 256-bit)" do
    context "for Int128" do
      subject(:type) { described_class.new("Int128") }

      it "handles large positive values" do
        large_value = 2**100
        expect(type.cast(large_value)).to eq(large_value)
      end

      it "handles large negative values" do
        large_value = -(2**100)
        expect(type.cast(large_value)).to eq(large_value)
      end

      it "handles maximum value" do
        max_value = (2**127) - 1
        expect(type.cast(max_value)).to eq(max_value)
      end

      it "raises for overflow" do
        expect { type.cast(2**127) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context "for UInt256" do
      subject(:type) { described_class.new("UInt256") }

      it "handles very large values" do
        large_value = 2**200
        expect(type.cast(large_value)).to eq(large_value)
      end

      it "handles maximum value" do
        max_value = (2**256) - 1
        expect(type.cast(max_value)).to eq(max_value)
      end

      it "raises for negative values" do
        expect { type.cast(-1) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end
  end
end
