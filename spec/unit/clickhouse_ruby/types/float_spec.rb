# frozen_string_literal: true

require 'spec_helper'
require 'bigdecimal'

RSpec.describe ClickhouseRuby::Types::Float do
  %w[Float32 Float64].each do |type_name|
    context "for #{type_name}" do
      subject(:type) { described_class.new(type_name) }

      describe '#name' do
        it "returns #{type_name}" do
          expect(type.name).to eq(type_name)
        end
      end
    end
  end

  describe '#cast' do
    subject(:type) { described_class.new('Float64') }

    context 'from Float' do
      it 'returns the float unchanged' do
        expect(type.cast(3.14)).to eq(3.14)
      end

      it 'returns negative floats' do
        expect(type.cast(-3.14)).to eq(-3.14)
      end

      it 'returns zero' do
        expect(type.cast(0.0)).to eq(0.0)
      end
    end

    context 'from Integer' do
      it 'converts to float' do
        expect(type.cast(42)).to eq(42.0)
      end

      it 'converts negative integers' do
        expect(type.cast(-42)).to eq(-42.0)
      end
    end

    context 'from String' do
      it 'parses float strings' do
        expect(type.cast('3.14')).to eq(3.14)
      end

      it 'parses negative float strings' do
        expect(type.cast('-3.14')).to eq(-3.14)
      end

      it 'parses scientific notation' do
        expect(type.cast('1.5e10')).to eq(1.5e10)
      end

      it 'parses strings with whitespace' do
        expect(type.cast('  3.14  ')).to eq(3.14)
      end

      it 'raises TypeCastError for non-numeric strings' do
        expect { type.cast('hello') }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'raises TypeCastError for empty strings' do
        expect { type.cast('') }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context 'from BigDecimal' do
      it 'converts to float' do
        expect(type.cast(BigDecimal('3.14'))).to eq(3.14)
      end
    end

    context 'from nil' do
      it 'returns nil' do
        expect(type.cast(nil)).to be_nil
      end
    end

    context 'from unsupported types' do
      it 'raises TypeCastError for arrays' do
        expect { type.cast([1, 2, 3]) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'raises TypeCastError for hashes' do
        expect { type.cast({ a: 1 }) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'raises TypeCastError for objects' do
        expect { type.cast(Object.new) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context 'special values' do
      it 'parses inf' do
        expect(type.cast('inf')).to eq(Float::INFINITY)
      end

      it 'parses +inf' do
        expect(type.cast('+inf')).to eq(Float::INFINITY)
      end

      it 'parses -inf' do
        expect(type.cast('-inf')).to eq(-Float::INFINITY)
      end

      it 'parses infinity' do
        expect(type.cast('infinity')).to eq(Float::INFINITY)
      end

      it 'parses nan' do
        expect(type.cast('nan').nan?).to be true
      end

      it 'parses case-insensitive' do
        expect(type.cast('INF')).to eq(Float::INFINITY)
        expect(type.cast('NaN').nan?).to be true
      end
    end

    context 'with TypeCastError details' do
      it 'includes from_type in error' do
        expect { type.cast('hello') }.to raise_error do |error|
          expect(error.from_type).to eq('String')
        end
      end

      it 'includes to_type in error' do
        expect { type.cast('hello') }.to raise_error do |error|
          expect(error.to_type).to eq('Float64')
        end
      end

      it 'includes value in error' do
        expect { type.cast('hello') }.to raise_error do |error|
          expect(error.value).to eq('hello')
        end
      end
    end
  end

  describe '#deserialize' do
    subject(:type) { described_class.new('Float64') }

    it 'returns nil for nil' do
      expect(type.deserialize(nil)).to be_nil
    end

    it 'returns float unchanged' do
      expect(type.deserialize(3.14)).to eq(3.14)
    end

    it 'parses string values' do
      expect(type.deserialize('3.14')).to eq(3.14)
    end

    it 'converts integers' do
      expect(type.deserialize(42)).to eq(42.0)
    end

    it 'converts BigDecimal' do
      expect(type.deserialize(BigDecimal('3.14'))).to eq(3.14)
    end

    it 'converts Rational' do
      expect(type.deserialize(Rational(22, 7))).to be_within(0.001).of(3.142857)
    end

    it 'handles special string values' do
      expect(type.deserialize('inf')).to eq(Float::INFINITY)
      expect(type.deserialize('-inf')).to eq(-Float::INFINITY)
      expect(type.deserialize('nan').nan?).to be true
    end

    context 'with unsupported types' do
      it 'raises TypeCastError for arrays' do
        expect { type.deserialize([1, 2, 3]) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'raises TypeCastError for hashes' do
        expect { type.deserialize({ a: 1 }) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'raises TypeCastError for arbitrary objects' do
        expect { type.deserialize(Object.new) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'includes error details' do
        expect { type.deserialize(Object.new) }.to raise_error do |error|
          expect(error).to be_a(ClickhouseRuby::TypeCastError)
          expect(error.to_type).to eq('Float64')
        end
      end
    end
  end

  describe '#serialize' do
    subject(:type) { described_class.new('Float64') }

    it 'converts to string' do
      expect(type.serialize(3.14)).to eq('3.14')
    end

    it 'handles zero' do
      expect(type.serialize(0.0)).to eq('0.0')
    end

    it 'handles negative values' do
      expect(type.serialize(-3.14)).to eq('-3.14')
    end

    it 'returns NULL for nil' do
      expect(type.serialize(nil)).to eq('NULL')
    end

    context 'special values' do
      it 'serializes infinity as inf' do
        expect(type.serialize(Float::INFINITY)).to eq('inf')
      end

      it 'serializes negative infinity as -inf' do
        expect(type.serialize(-Float::INFINITY)).to eq('-inf')
      end

      it 'serializes NaN as nan' do
        expect(type.serialize(Float::NAN)).to eq('nan')
      end
    end
  end
end
