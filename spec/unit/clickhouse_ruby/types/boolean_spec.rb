# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Types::Boolean do
  subject(:type) { described_class.new("Bool") }

  describe "#name" do
    it "returns Bool" do
      expect(type.name).to eq("Bool")
    end
  end

  describe "#cast" do
    context "from nil" do
      it "returns nil" do
        expect(type.cast(nil)).to be_nil
      end
    end

    context "truthy values" do
      [true, 1, "1", "true", "TRUE", "True", "t", "T", "yes", "YES", "Yes", "y", "Y", "on", "ON", "On"].each do |value|
        it "casts #{value.inspect} to true" do
          expect(type.cast(value)).to be true
        end
      end
    end

    context "falsy values" do
      [false, 0, "0", "false", "FALSE", "False", "f", "F", "no", "NO", "No", "n", "N", "off", "OFF", "Off"].each do |value|
        it "casts #{value.inspect} to false" do
          expect(type.cast(value)).to be false
        end
      end
    end

    context "invalid values" do
      it "raises TypeCastError for invalid strings" do
        expect { type.cast("maybe") }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises TypeCastError for numbers other than 0/1" do
        expect { type.cast(2) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises TypeCastError for arrays" do
        expect { type.cast([]) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "raises TypeCastError for empty string" do
        expect { type.cast("") }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it "includes error details" do
        expect { type.cast("maybe") }.to raise_error do |error|
          expect(error.from_type).to eq("String")
          expect(error.to_type).to eq("Bool")
          expect(error.value).to eq("maybe")
        end
      end
    end
  end

  describe "#deserialize" do
    context "from nil" do
      it "returns nil" do
        expect(type.deserialize(nil)).to be_nil
      end
    end

    context "truthy values" do
      it "deserializes true to true" do
        expect(type.deserialize(true)).to be true
      end

      it "deserializes 1 to true" do
        expect(type.deserialize(1)).to be true
      end

      it 'deserializes "1" to true' do
        expect(type.deserialize("1")).to be true
      end

      it 'deserializes "true" to true' do
        expect(type.deserialize("true")).to be true
      end
    end

    context "falsy values" do
      it "deserializes false to false" do
        expect(type.deserialize(false)).to be false
      end

      it "deserializes 0 to false" do
        expect(type.deserialize(0)).to be false
      end

      it 'deserializes "0" to false' do
        expect(type.deserialize("0")).to be false
      end

      it 'deserializes "false" to false' do
        expect(type.deserialize("false")).to be false
      end
    end

    context "other values" do
      it "uses truthy evaluation for other values" do
        expect(type.deserialize("anything")).to be true
        expect(type.deserialize(42)).to be true
      end
    end
  end

  describe "#serialize" do
    context "from nil" do
      it "returns NULL" do
        expect(type.serialize(nil)).to eq("NULL")
      end
    end

    context "from true" do
      it "returns 1" do
        expect(type.serialize(true)).to eq("1")
      end
    end

    context "from false" do
      it "returns 0" do
        expect(type.serialize(false)).to eq("0")
      end
    end

    context "from truthy values" do
      it "returns 1 for truthy values" do
        expect(type.serialize(1)).to eq("1")
        expect(type.serialize("yes")).to eq("1")
      end
    end

    context "from falsy values" do
      it "returns 0 for values in FALSE_VALUES" do
        expect(type.serialize(0)).to eq("0")
        expect(type.serialize("0")).to eq("0")
        expect(type.serialize("false")).to eq("0")
        expect(type.serialize("no")).to eq("0")
        expect(type.serialize("off")).to eq("0")
      end
    end
  end

  describe "TRUE_VALUES constant" do
    it "is frozen" do
      expect(described_class::TRUE_VALUES).to be_frozen
    end

    it "contains expected values" do
      expect(described_class::TRUE_VALUES).to include(true, 1, "1", "true", "yes", "on")
    end
  end

  describe "FALSE_VALUES constant" do
    it "is frozen" do
      expect(described_class::FALSE_VALUES).to be_frozen
    end

    it "contains expected values" do
      expect(described_class::FALSE_VALUES).to include(false, 0, "0", "false", "no", "off")
    end
  end
end
