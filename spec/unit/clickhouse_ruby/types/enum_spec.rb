# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Types::Enum do
  describe "Enum type" do
    subject(:type) { described_class.new("Enum8('active' = 1, 'inactive' = 2, 'pending' = 3)") }

    describe "#initialize" do
      it "parses enum values" do
        expect(type.possible_values).to eq(%w[active inactive pending])
      end

      it "builds value-to-int mapping" do
        expect(type.value_to_int).to eq({ "active" => 1, "inactive" => 2, "pending" => 3 })
      end

      it "builds int-to-value mapping" do
        expect(type.int_to_value).to eq({ 1 => "active", 2 => "inactive", 3 => "pending" })
      end
    end

    describe "#cast" do
      context "cast string to valid enum value" do
        it "returns the string unchanged" do
          expect(type.cast("active")).to eq("active")
        end
      end

      context "cast integer to enum value" do
        it "converts 1 to active" do
          expect(type.cast(1)).to eq("active")
        end

        it "converts 2 to inactive" do
          expect(type.cast(2)).to eq("inactive")
        end

        it "converts 3 to pending" do
          expect(type.cast(3)).to eq("pending")
        end
      end

      context "cast invalid string" do
        it "raises TypeCastError for unknown string value" do
          expect { type.cast("unknown") }.to raise_error(ClickhouseRuby::TypeCastError)
        end
      end

      context "cast invalid integer" do
        it "raises TypeCastError for unknown integer value" do
          expect { type.cast(99) }.to raise_error(ClickhouseRuby::TypeCastError)
        end
      end

      context "cast nil" do
        it "returns nil" do
          expect(type.cast(nil)).to be_nil
        end
      end

      context "cast unsupported type" do
        it "raises TypeCastError for unsupported type" do
          expect { type.cast([]) }.to raise_error(ClickhouseRuby::TypeCastError)
        end
      end
    end

    describe "#deserialize" do
      it "returns string representation from ClickHouse" do
        expect(type.deserialize("active")).to eq("active")
      end

      it "converts integer to string" do
        expect(type.deserialize(1)).to eq("1")
      end
    end

    describe "#serialize" do
      it "quotes valid enum value" do
        expect(type.serialize("active")).to eq("'active'")
      end

      it "returns NULL for nil" do
        expect(type.serialize(nil)).to eq("NULL")
      end

      it "escapes quotes in enum values" do
        # For enum like Enum("it's" = 1)
        expect(type.serialize("it's")).to eq("'it\\'s'")
      end
    end

    describe "with auto-increment values" do
      subject(:type_auto) { described_class.new("Enum('hello', 'world')") }

      it "parses enum values with auto-increment" do
        expect(type_auto.possible_values).to eq(%w[hello world])
      end

      it "assigns auto-incremented integer values" do
        expect(type_auto.value_to_int).to eq({ "hello" => 1, "world" => 2 })
      end
    end

    describe "with Enum16 type" do
      subject(:type_16) { described_class.new("Enum16('a' = 100, 'b' = 200)") }

      it "parses Enum16 values" do
        expect(type_16.possible_values).to eq(%w[a b])
      end

      it "handles large integers for Enum16" do
        expect(type_16.value_to_int).to eq({ "a" => 100, "b" => 200 })
      end

      it "casts large integer to value" do
        expect(type_16.cast(100)).to eq("a")
      end
    end

    describe "with special characters in enum values" do
      subject(:type_special) { described_class.new("Enum('it\\'s ok' = 1, 'value, test' = 2)") }

      it "parses escaped quotes" do
        expect(type_special.possible_values).to include("it's ok")
      end

      it "casts special character values" do
        expect(type_special.cast("it's ok")).to eq("it's ok")
      end
    end
  end
end
