# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickhouseRuby::Types::Tuple do
  describe '#initialize' do
    it 'accepts element types' do
      string_type = ClickhouseRuby::Types::Base.new('String')
      int_type = ClickhouseRuby::Types::Integer.new('UInt64')
      type = described_class.new('Tuple', arg_types: [string_type, int_type])

      expect(type.element_types).to eq([string_type, int_type])
    end

    it 'defaults to empty element types' do
      type = described_class.new('Tuple')
      expect(type.element_types).to eq([])
    end
  end

  describe '#to_s' do
    it 'returns the full type string' do
      string_type = ClickhouseRuby::Types::Base.new('String')
      int_type = ClickhouseRuby::Types::Integer.new('UInt64')
      type = described_class.new('Tuple', arg_types: [string_type, int_type])
      expect(type.to_s).to eq('Tuple(String, UInt64)')
    end

    it 'returns empty tuple for no elements' do
      type = described_class.new('Tuple')
      expect(type.to_s).to eq('Tuple()')
    end
  end

  describe '#cast' do
    context 'with String and UInt64 elements' do
      subject(:type) do
        string_type = ClickhouseRuby::Types::Base.new('String')
        int_type = ClickhouseRuby::Types::Integer.new('UInt64')
        described_class.new('Tuple', arg_types: [string_type, int_type])
      end

      it 'casts arrays' do
        expect(type.cast(['hello', 42])).to eq(['hello', 42])
      end

      it 'casts string values to appropriate types' do
        expect(type.cast(['hello', '42'])).to eq(['hello', 42])
      end

      it 'returns nil for nil input' do
        expect(type.cast(nil)).to be_nil
      end

      it 'returns empty array for empty input' do
        expect(type.cast([])).to eq([])
      end
    end

    context 'from string representation' do
      subject(:type) do
        string_type = ClickhouseRuby::Types::Base.new('String')
        int_type = ClickhouseRuby::Types::Integer.new('Int32')
        described_class.new('Tuple', arg_types: [string_type, int_type])
      end

      it 'parses tuple string format' do
        expect(type.cast("('hello', 42)")).to eq(['hello', 42])
      end

      it 'parses empty tuple string' do
        expect(type.cast('()')).to eq([])
      end

      it 'handles quoted strings' do
        expect(type.cast("('world', 100)")).to eq(['world', 100])
      end

      it 'raises TypeCastError for invalid format' do
        expect { type.cast('not a tuple') }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end

    context 'from unsupported types' do
      subject(:type) { described_class.new('Tuple') }

      it 'raises TypeCastError for hashes' do
        expect { type.cast({ a: 1 }) }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'raises TypeCastError for integers' do
        expect { type.cast(42) }.to raise_error(ClickhouseRuby::TypeCastError)
      end
    end
  end

  describe '#deserialize' do
    subject(:type) do
      string_type = ClickhouseRuby::Types::Base.new('String')
      int_type = ClickhouseRuby::Types::Integer.new('Int32')
      described_class.new('Tuple', arg_types: [string_type, int_type])
    end

    it 'deserializes arrays' do
      expect(type.deserialize(['hello', 42])).to eq(['hello', 42])
    end

    it 'deserializes string representations' do
      expect(type.deserialize("('hello', 42)")).to eq(['hello', 42])
    end

    it 'returns nil for nil' do
      expect(type.deserialize(nil)).to be_nil
    end

    it 'raises error for non-tuple string format' do
      expect { type.deserialize('hello') }.to raise_error(ClickhouseRuby::TypeCastError)
    end
  end

  describe '#serialize' do
    subject(:type) do
      string_type = ClickhouseRuby::Types::Base.new('String')
      int_type = ClickhouseRuby::Types::Integer.new('Int32')
      described_class.new('Tuple', arg_types: [string_type, int_type])
    end

    it 'serializes tuples to SQL format' do
      expect(type.serialize(['hello', 42])).to eq('(hello, 42)')
    end

    it 'serializes empty tuples' do
      expect(type.serialize([])).to eq('()')
    end

    it 'returns NULL for nil' do
      expect(type.serialize(nil)).to eq('NULL')
    end
  end

  describe 'tuples with many elements' do
    context 'Tuple(String, Int32, Float64, Bool)' do
      subject(:type) do
        types = [
          ClickhouseRuby::Types::Base.new('String'),
          ClickhouseRuby::Types::Integer.new('Int32'),
          ClickhouseRuby::Types::Base.new('Float64'),
          ClickhouseRuby::Types::Base.new('Bool')
        ]
        described_class.new('Tuple', arg_types: types)
      end

      it 'casts tuples with multiple elements' do
        input = ['hello', 42, 3.14, true]
        result = type.cast(input)
        expect(result[0]).to eq('hello')
        expect(result[1]).to eq(42)
      end

      it 'returns the correct type string' do
        expect(type.to_s).to eq('Tuple(String, Int32, Float64, Bool)')
      end
    end
  end

  describe 'nested tuple types' do
    context 'Tuple(String, Tuple(Int32, Int32))' do
      subject(:type) do
        inner_tuple = described_class.new('Tuple', arg_types: [
          ClickhouseRuby::Types::Integer.new('Int32'),
          ClickhouseRuby::Types::Integer.new('Int32')
        ])
        string_type = ClickhouseRuby::Types::Base.new('String')
        described_class.new('Tuple', arg_types: [string_type, inner_tuple])
      end

      it 'casts nested tuples' do
        input = ['hello', [1, 2]]
        expect(type.cast(input)).to eq(['hello', [1, 2]])
      end

      it 'returns the correct type string' do
        expect(type.to_s).to eq('Tuple(String, Tuple(Int32, Int32))')
      end
    end

    context 'Tuple(String, Array(Int32))' do
      subject(:type) do
        string_type = ClickhouseRuby::Types::Base.new('String')
        array_type = ClickhouseRuby::Types::Array.new('Array', element_type: ClickhouseRuby::Types::Integer.new('Int32'))
        described_class.new('Tuple', arg_types: [string_type, array_type])
      end

      it 'casts tuples with array elements' do
        input = ['hello', [1, 2, 3]]
        expect(type.cast(input)).to eq(['hello', [1, 2, 3]])
      end

      it 'returns the correct type string' do
        expect(type.to_s).to eq('Tuple(String, Array(Int32))')
      end
    end
  end

  describe 'tuples with nullable elements' do
    context 'Tuple(String, Nullable(Int32))' do
      subject(:type) do
        string_type = ClickhouseRuby::Types::Base.new('String')
        nullable_int = ClickhouseRuby::Types::Nullable.new('Nullable', element_type: ClickhouseRuby::Types::Integer.new('Int32'))
        described_class.new('Tuple', arg_types: [string_type, nullable_int])
      end

      it 'casts tuples with nil elements' do
        expect(type.cast(['hello', nil])).to eq(['hello', nil])
      end

      it 'casts tuples with non-nil elements' do
        expect(type.cast(['hello', 42])).to eq(['hello', 42])
      end

      it 'serializes tuples with null elements' do
        expect(type.serialize(['hello', nil])).to eq('(hello, NULL)')
      end
    end
  end

  describe 'string parsing edge cases' do
    subject(:type) do
      string_type = ClickhouseRuby::Types::Base.new('String')
      described_class.new('Tuple', arg_types: [string_type, string_type])
    end

    it 'handles strings with commas' do
      expect(type.cast("('a, b', 'c')")).to eq(['a, b', 'c'])
    end

    it 'handles strings with parentheses' do
      expect(type.cast("('(test)', 'ok')")).to eq(['(test)', 'ok'])
    end

    it 'handles escaped quotes' do
      expect(type.cast("('it\\'s', 'ok')")).to eq(["it's", 'ok'])
    end

    it 'handles nested tuple strings' do
      inner_tuple = described_class.new('Tuple', arg_types: [
        ClickhouseRuby::Types::Integer.new('Int32'),
        ClickhouseRuby::Types::Integer.new('Int32')
      ])
      nested_type = described_class.new('Tuple', arg_types: [
        ClickhouseRuby::Types::Base.new('String'),
        inner_tuple
      ])

      result = nested_type.deserialize("('hello', (1, 2))")
      expect(result[0]).to eq('hello')
      expect(result[1]).to eq([1, 2])
    end
  end
end
