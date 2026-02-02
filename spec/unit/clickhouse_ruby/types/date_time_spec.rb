# frozen_string_literal: true

require "spec_helper"
require "time"
require "date"

RSpec.describe ClickhouseRuby::Types::DateTime do
  describe "Date type" do
    subject(:type) { described_class.new("Date") }

    describe "#name" do
      it "returns Date" do
        expect(type.name).to eq("Date")
      end
    end

    describe "#date_only?" do
      it "returns true" do
        expect(type.date_only?).to be true
      end
    end

    describe "#cast" do
      context "from nil" do
        it "returns nil" do
          expect(type.cast(nil)).to be_nil
        end
      end

      context "from Date" do
        it "returns the date unchanged" do
          date = Date.new(2024, 1, 15)
          expect(type.cast(date)).to eq(date)
        end
      end

      context "from Time" do
        it "converts to date" do
          time = Time.new(2024, 1, 15, 10, 30, 0)
          expect(type.cast(time)).to eq(Date.new(2024, 1, 15))
        end
      end

      context "from String" do
        it "parses date strings" do
          expect(type.cast("2024-01-15")).to eq(Date.new(2024, 1, 15))
        end

        it "raises TypeCastError for invalid strings" do
          expect { type.cast("not-a-date") }.to raise_error(ClickhouseRuby::TypeCastError)
        end

        it "raises TypeCastError for empty strings" do
          expect { type.cast("") }.to raise_error(ClickhouseRuby::TypeCastError)
        end
      end

      context "from Integer (unix timestamp)" do
        it "converts to date" do
          timestamp = Time.new(2024, 1, 15).to_i
          expect(type.cast(timestamp)).to eq(Date.new(2024, 1, 15))
        end
      end

      context "from unsupported types" do
        it "raises TypeCastError" do
          expect { type.cast([]) }.to raise_error(ClickhouseRuby::TypeCastError)
        end
      end
    end

    describe "#deserialize" do
      context "from nil" do
        it "returns nil" do
          expect(type.deserialize(nil)).to be_nil
        end
      end

      context "from Date" do
        it "returns the date" do
          date = Date.new(2024, 1, 15)
          expect(type.deserialize(date)).to eq(date)
        end
      end

      context "from String" do
        it "parses date strings" do
          expect(type.deserialize("2024-01-15")).to eq(Date.new(2024, 1, 15))
        end
      end

      context "from Integer" do
        it "converts to date" do
          timestamp = Time.new(2024, 1, 15).to_i
          expect(type.deserialize(timestamp)).to eq(Date.new(2024, 1, 15))
        end
      end
    end

    describe "#serialize" do
      context "from nil" do
        it "returns NULL" do
          expect(type.serialize(nil)).to eq("NULL")
        end
      end

      context "from Date" do
        it "formats as quoted date string" do
          date = Date.new(2024, 1, 15)
          expect(type.serialize(date)).to eq("'2024-01-15'")
        end
      end

      context "from Time" do
        it "extracts and formats date" do
          time = Time.new(2024, 1, 15, 10, 30)
          expect(type.serialize(time)).to eq("'2024-01-15'")
        end
      end
    end
  end

  describe "Date32 type" do
    subject(:type) { described_class.new("Date32") }

    describe "#date_only?" do
      it "returns true" do
        expect(type.date_only?).to be true
      end
    end

    it "handles dates in extended range" do
      early_date = Date.new(1900, 1, 1)
      expect(type.cast(early_date)).to eq(early_date)
    end
  end

  describe "DateTime type" do
    subject(:type) { described_class.new("DateTime") }

    describe "#name" do
      it "returns DateTime" do
        expect(type.name).to eq("DateTime")
      end
    end

    describe "#date_only?" do
      it "returns false" do
        expect(type.date_only?).to be false
      end
    end

    describe "#cast" do
      context "from nil" do
        it "returns nil" do
          expect(type.cast(nil)).to be_nil
        end
      end

      context "from Time" do
        it "returns the time unchanged" do
          time = Time.new(2024, 1, 15, 10, 30, 0)
          expect(type.cast(time)).to eq(time)
        end
      end

      context "from Date" do
        it "converts to time" do
          date = Date.new(2024, 1, 15)
          result = type.cast(date)
          expect(result).to be_a(Time)
          expect(result.year).to eq(2024)
          expect(result.month).to eq(1)
          expect(result.day).to eq(15)
        end
      end

      context "from String" do
        it "parses datetime strings" do
          result = type.cast("2024-01-15 10:30:00")
          expect(result.year).to eq(2024)
          expect(result.hour).to eq(10)
          expect(result.min).to eq(30)
        end

        it "raises TypeCastError for invalid strings" do
          expect { type.cast("not-a-datetime") }.to raise_error(ClickhouseRuby::TypeCastError)
        end
      end

      context "from Integer (unix timestamp)" do
        it "converts to time" do
          timestamp = 1_705_312_200 # 2024-01-15 10:30:00 UTC
          result = type.cast(timestamp)
          expect(result).to be_a(Time)
          expect(result.to_i).to eq(timestamp)
        end
      end
    end

    describe "#deserialize" do
      context "from String" do
        it "parses datetime strings" do
          result = type.deserialize("2024-01-15 10:30:00")
          expect(result).to be_a(Time)
        end
      end

      context "from Time" do
        it "returns as time" do
          time = Time.new(2024, 1, 15, 10, 30, 0)
          expect(type.deserialize(time)).to eq(time)
        end
      end
    end

    describe "#serialize" do
      context "from nil" do
        it "returns NULL" do
          expect(type.serialize(nil)).to eq("NULL")
        end
      end

      context "from Time" do
        it "formats as quoted datetime string" do
          time = Time.new(2024, 1, 15, 10, 30, 45)
          expect(type.serialize(time)).to eq("'2024-01-15 10:30:45'")
        end
      end
    end
  end

  describe "DateTime64 type" do
    context "with precision 3 (milliseconds)" do
      subject(:type) { described_class.new("DateTime64(3)", precision: 3) }

      describe "#precision" do
        it "returns 3" do
          expect(type.precision).to eq(3)
        end
      end

      describe "#serialize" do
        it "includes milliseconds" do
          time = Time.new(2024, 1, 15, 10, 30, 45.123)
          result = type.serialize(time)
          expect(result).to match(/'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}'/)
        end
      end
    end

    context "with precision 6 (microseconds)" do
      subject(:type) { described_class.new("DateTime64(6)", precision: 6) }

      describe "#precision" do
        it "returns 6" do
          expect(type.precision).to eq(6)
        end
      end

      describe "#serialize" do
        it "includes microseconds" do
          time = Time.new(2024, 1, 15, 10, 30, 45.123456)
          result = type.serialize(time)
          expect(result).to match(/'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}'/)
        end
      end
    end
  end

  describe "DateTime with timezone" do
    subject(:type) { described_class.new("DateTime('UTC')", timezone: "UTC") }

    describe "#timezone" do
      it "returns the timezone" do
        expect(type.timezone).to eq("UTC")
      end
    end
  end

  describe "error handling" do
    subject(:type) { described_class.new("DateTime") }

    it "includes from_type in error" do
      expect { type.cast("invalid") }.to raise_error do |error|
        expect(error.from_type).to eq("String")
      end
    end

    it "includes to_type in error" do
      expect { type.cast("invalid") }.to raise_error do |error|
        expect(error.to_type).to eq("DateTime")
      end
    end

    it "includes value in error" do
      expect { type.cast("invalid") }.to raise_error do |error|
        expect(error.value).to eq("invalid")
      end
    end
  end
end
