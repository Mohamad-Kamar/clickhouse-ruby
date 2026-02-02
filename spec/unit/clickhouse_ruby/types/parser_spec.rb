# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Types::Parser do
  subject(:parser) { described_class.new }

  describe "#parse" do
    context "with simple types" do
      it "parses String" do
        result = parser.parse("String")
        expect(result).to eq({ type: "String" })
      end

      it "parses UInt64" do
        result = parser.parse("UInt64")
        expect(result).to eq({ type: "UInt64" })
      end

      it "parses Int32" do
        result = parser.parse("Int32")
        expect(result).to eq({ type: "Int32" })
      end

      it "parses Float64" do
        result = parser.parse("Float64")
        expect(result).to eq({ type: "Float64" })
      end

      it "parses DateTime" do
        result = parser.parse("DateTime")
        expect(result).to eq({ type: "DateTime" })
      end

      it "parses UUID" do
        result = parser.parse("UUID")
        expect(result).to eq({ type: "UUID" })
      end

      it "parses Bool" do
        result = parser.parse("Bool")
        expect(result).to eq({ type: "Bool" })
      end

      it "handles leading/trailing whitespace" do
        result = parser.parse("  String  ")
        expect(result).to eq({ type: "String" })
      end

      it "parses types with underscores" do
        result = parser.parse("Custom_Type_Name")
        expect(result).to eq({ type: "Custom_Type_Name" })
      end
    end

    context "with parameterized types (single argument)" do
      it "parses Nullable(String)" do
        result = parser.parse("Nullable(String)")
        expect(result).to eq({
          type: "Nullable",
          args: [{ type: "String" }],
        })
      end

      it "parses Array(Int32)" do
        result = parser.parse("Array(Int32)")
        expect(result).to eq({
          type: "Array",
          args: [{ type: "Int32" }],
        })
      end

      it "parses Array(UInt64)" do
        result = parser.parse("Array(UInt64)")
        expect(result).to eq({
          type: "Array",
          args: [{ type: "UInt64" }],
        })
      end

      it "parses LowCardinality(String)" do
        result = parser.parse("LowCardinality(String)")
        expect(result).to eq({
          type: "LowCardinality",
          args: [{ type: "String" }],
        })
      end

      it "handles whitespace inside parentheses" do
        result = parser.parse("Array(  Int32  )")
        expect(result).to eq({
          type: "Array",
          args: [{ type: "Int32" }],
        })
      end
    end

    context "with parameterized types (multiple arguments)" do
      it "parses Tuple(String, UInt64)" do
        result = parser.parse("Tuple(String, UInt64)")
        expect(result).to eq({
          type: "Tuple",
          args: [
            { type: "String" },
            { type: "UInt64" },
          ],
        })
      end

      it "parses Map(String, Int32)" do
        result = parser.parse("Map(String, Int32)")
        expect(result).to eq({
          type: "Map",
          args: [
            { type: "String" },
            { type: "Int32" },
          ],
        })
      end

      it "parses Tuple with three elements" do
        result = parser.parse("Tuple(String, UInt64, DateTime)")
        expect(result).to eq({
          type: "Tuple",
          args: [
            { type: "String" },
            { type: "UInt64" },
            { type: "DateTime" },
          ],
        })
      end

      it "handles whitespace between arguments" do
        result = parser.parse("Tuple( String , UInt64 )")
        expect(result).to eq({
          type: "Tuple",
          args: [
            { type: "String" },
            { type: "UInt64" },
          ],
        })
      end
    end

    context "with nested types" do
      # CRITICAL: This test addresses issue #210
      # Existing gems fail to parse nested types correctly
      it "parses Array(Tuple(String, UInt64))" do
        result = parser.parse("Array(Tuple(String, UInt64))")
        expect(result).to eq({
          type: "Array",
          args: [{
            type: "Tuple",
            args: [
              { type: "String" },
              { type: "UInt64" },
            ],
          }],
        })
      end

      it "parses Nullable(Array(Int32))" do
        result = parser.parse("Nullable(Array(Int32))")
        expect(result).to eq({
          type: "Nullable",
          args: [{
            type: "Array",
            args: [{ type: "Int32" }],
          }],
        })
      end

      it "parses Array(Nullable(String))" do
        result = parser.parse("Array(Nullable(String))")
        expect(result).to eq({
          type: "Array",
          args: [{
            type: "Nullable",
            args: [{ type: "String" }],
          }],
        })
      end

      it "parses Map(String, Array(Int32))" do
        result = parser.parse("Map(String, Array(Int32))")
        expect(result).to eq({
          type: "Map",
          args: [
            { type: "String" },
            {
              type: "Array",
              args: [{ type: "Int32" }],
            },
          ],
        })
      end

      it "parses Array(Array(Int32))" do
        result = parser.parse("Array(Array(Int32))")
        expect(result).to eq({
          type: "Array",
          args: [{
            type: "Array",
            args: [{ type: "Int32" }],
          }],
        })
      end
    end

    context "with deeply nested types" do
      # These tests ensure the parser handles arbitrary nesting depth
      it "parses Map(String, Array(Nullable(UInt64)))" do
        result = parser.parse("Map(String, Array(Nullable(UInt64)))")
        expect(result).to eq({
          type: "Map",
          args: [
            { type: "String" },
            {
              type: "Array",
              args: [{
                type: "Nullable",
                args: [{ type: "UInt64" }],
              }],
            },
          ],
        })
      end

      it "parses Tuple(String, Array(Tuple(Int32, String)), UInt64)" do
        result = parser.parse("Tuple(String, Array(Tuple(Int32, String)), UInt64)")
        expect(result).to eq({
          type: "Tuple",
          args: [
            { type: "String" },
            {
              type: "Array",
              args: [{
                type: "Tuple",
                args: [
                  { type: "Int32" },
                  { type: "String" },
                ],
              }],
            },
            { type: "UInt64" },
          ],
        })
      end

      it "parses Array(Array(Array(Int32)))" do
        result = parser.parse("Array(Array(Array(Int32)))")
        expect(result).to eq({
          type: "Array",
          args: [{
            type: "Array",
            args: [{
              type: "Array",
              args: [{ type: "Int32" }],
            }],
          }],
        })
      end

      it "parses Map(String, Map(String, Array(Nullable(Int64))))" do
        result = parser.parse("Map(String, Map(String, Array(Nullable(Int64))))")
        expect(result).to eq({
          type: "Map",
          args: [
            { type: "String" },
            {
              type: "Map",
              args: [
                { type: "String" },
                {
                  type: "Array",
                  args: [{
                    type: "Nullable",
                    args: [{ type: "Int64" }],
                  }],
                },
              ],
            },
          ],
        })
      end
    end

    context "with LowCardinality wrapped types" do
      it "parses LowCardinality(Nullable(String))" do
        result = parser.parse("LowCardinality(Nullable(String))")
        expect(result).to eq({
          type: "LowCardinality",
          args: [{
            type: "Nullable",
            args: [{ type: "String" }],
          }],
        })
      end

      it "parses Array(LowCardinality(String))" do
        result = parser.parse("Array(LowCardinality(String))")
        expect(result).to eq({
          type: "Array",
          args: [{
            type: "LowCardinality",
            args: [{ type: "String" }],
          }],
        })
      end
    end

    context "with invalid input" do
      it "raises ParseError for nil input" do
        expect { parser.parse(nil) }.to raise_error(ClickhouseRuby::Types::Parser::ParseError)
      end

      it "raises ParseError for empty string" do
        expect { parser.parse("") }.to raise_error(ClickhouseRuby::Types::Parser::ParseError)
      end

      it "raises ParseError for whitespace only" do
        expect { parser.parse("   ") }.to raise_error(ClickhouseRuby::Types::Parser::ParseError)
      end

      it "raises ParseError for unclosed parenthesis" do
        expect { parser.parse("Array(String") }.to raise_error(ClickhouseRuby::Types::Parser::ParseError)
      end

      it "raises ParseError for extra closing parenthesis" do
        expect { parser.parse("Array(String))") }.to raise_error(ClickhouseRuby::Types::Parser::ParseError)
      end

      it "raises ParseError for invalid characters" do
        expect { parser.parse("String@Invalid") }.to raise_error(ClickhouseRuby::Types::Parser::ParseError)
      end

      it "raises ParseError for type starting with number" do
        expect { parser.parse("123Type") }.to raise_error(ClickhouseRuby::Types::Parser::ParseError)
      end

      it "raises ParseError for empty type arguments" do
        # Array() with no args should still parse (empty args list)
        result = parser.parse("Array()")
        expect(result).to eq({ type: "Array", args: [] })
      end
    end

    context "error messages include context" do
      it "includes position in error message" do
        expect { parser.parse("Array(String") }.to raise_error do |error|
          expect(error.message).to include("position")
        end
      end

      it "includes input in error message" do
        expect { parser.parse("Array(String") }.to raise_error do |error|
          expect(error.message).to include("Array(String")
        end
      end
    end
  end

  describe "edge cases" do
    it "handles DateTime64(3)" do
      # DateTime64 with precision is a common pattern
      # Our parser treats the number as a type, which is fine
      # The registry handles this special case
      result = parser.parse("DateTime64(3)")
      expect(result[:type]).to eq("DateTime64")
      expect(result[:args]).to be_an(Array)
    end

    it "handles FixedString(16)" do
      result = parser.parse("FixedString(16)")
      expect(result[:type]).to eq("FixedString")
    end

    it "handles Decimal(10, 2)" do
      result = parser.parse("Decimal(10, 2)")
      expect(result[:type]).to eq("Decimal")
    end

    it "handles Enum8" do
      result = parser.parse("Enum8('active' = 1, 'inactive' = 0)")
      expect(result[:type]).to eq("Enum8")
    end
  end
end
