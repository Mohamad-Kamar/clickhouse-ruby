# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickhouseRuby::Types::String do
  describe 'String type' do
    subject(:type) { described_class.new('String') }

    describe '#name' do
      it 'returns String' do
        expect(type.name).to eq('String')
      end
    end

    describe '#length' do
      it 'returns nil for String type' do
        expect(type.length).to be_nil
      end
    end

    describe '#cast' do
      context 'from nil' do
        it 'returns nil' do
          expect(type.cast(nil)).to be_nil
        end
      end

      context 'from String' do
        it 'returns the string unchanged' do
          expect(type.cast('hello')).to eq('hello')
        end
      end

      context 'from other types' do
        it 'converts integers to string' do
          expect(type.cast(42)).to eq('42')
        end

        it 'converts floats to string' do
          expect(type.cast(3.14)).to eq('3.14')
        end

        it 'converts symbols to string' do
          expect(type.cast(:hello)).to eq('hello')
        end

        it 'converts arrays to string' do
          expect(type.cast([1, 2, 3])).to eq('[1, 2, 3]')
        end
      end
    end

    describe '#deserialize' do
      context 'from nil' do
        it 'returns nil' do
          expect(type.deserialize(nil)).to be_nil
        end
      end

      context 'from String' do
        it 'returns the string' do
          expect(type.deserialize('hello')).to eq('hello')
        end
      end

      context 'from other types' do
        it 'converts to string' do
          expect(type.deserialize(42)).to eq('42')
        end
      end
    end

    describe '#serialize' do
      context 'from nil' do
        it 'returns NULL' do
          expect(type.serialize(nil)).to eq('NULL')
        end
      end

      context 'from String' do
        it 'quotes the string' do
          expect(type.serialize('hello')).to eq("'hello'")
        end
      end

      context 'escaping' do
        it 'escapes backslashes' do
          expect(type.serialize('back\\slash')).to eq("'back\\\\slash'")
        end

        it 'escapes single quotes' do
          expect(type.serialize("it's")).to eq("'it\\'s'")
        end

        it 'escapes newlines' do
          expect(type.serialize("line1\nline2")).to eq("'line1\\nline2'")
        end

        it 'escapes carriage returns' do
          expect(type.serialize("line1\rline2")).to eq("'line1\\rline2'")
        end

        it 'escapes tabs' do
          expect(type.serialize("col1\tcol2")).to eq("'col1\\tcol2'")
        end

        it 'escapes null bytes' do
          expect(type.serialize("hello\0world")).to eq("'hello\\0world'")
        end

        it 'handles multiple special characters' do
          expect(type.serialize("it's a\nnew \"line\" with\ttab")).to eq("'it\\'s a\\nnew \"line\" with\\ttab'")
        end
      end
    end
  end

  describe 'FixedString type' do
    subject(:type) { described_class.new('FixedString(10)', length: 10) }

    describe '#name' do
      it 'returns FixedString(10)' do
        expect(type.name).to eq('FixedString(10)')
      end
    end

    describe '#length' do
      it 'returns 10' do
        expect(type.length).to eq(10)
      end
    end

    describe '#cast' do
      context 'from nil' do
        it 'returns nil' do
          expect(type.cast(nil)).to be_nil
        end
      end

      context 'with shorter string' do
        it 'pads with null bytes' do
          result = type.cast('hello')
          expect(result.length).to eq(10)
          expect(result).to start_with('hello')
          expect(result[5..]).to eq("\0" * 5)
        end
      end

      context 'with exact length string' do
        it 'returns unchanged' do
          expect(type.cast('1234567890').length).to eq(10)
        end
      end

      context 'with longer string' do
        it 'truncates to fixed length' do
          result = type.cast('this is a very long string')
          expect(result.length).to eq(10)
          expect(result).to eq('this is a ')
        end
      end
    end

    describe '#deserialize' do
      context 'with null-padded string' do
        it 'removes trailing null bytes' do
          expect(type.deserialize("hello\0\0\0\0\0")).to eq('hello')
        end
      end

      context 'with no null bytes' do
        it 'returns the string' do
          expect(type.deserialize('1234567890')).to eq('1234567890')
        end
      end

      context 'from nil' do
        it 'returns nil' do
          expect(type.deserialize(nil)).to be_nil
        end
      end
    end

    describe '#serialize' do
      it 'quotes the string' do
        expect(type.serialize('hello')).to eq("'hello'")
      end

      it 'escapes special characters' do
        expect(type.serialize("it's")).to eq("'it\\'s'")
      end
    end
  end

  describe 'empty string handling' do
    subject(:type) { described_class.new('String') }

    it 'casts empty string correctly' do
      expect(type.cast('')).to eq('')
    end

    it 'deserializes empty string correctly' do
      expect(type.deserialize('')).to eq('')
    end

    it 'serializes empty string correctly' do
      expect(type.serialize('')).to eq("''")
    end
  end

  describe 'unicode handling' do
    subject(:type) { described_class.new('String') }

    it 'handles unicode characters' do
      expect(type.cast('hello 世界')).to eq('hello 世界')
    end

    it 'deserializes unicode correctly' do
      expect(type.deserialize('hello 世界')).to eq('hello 世界')
    end

    it 'serializes unicode correctly' do
      expect(type.serialize('hello 世界')).to eq("'hello 世界'")
    end
  end

  describe 'binary data' do
    subject(:type) { described_class.new('String') }

    it 'handles binary data' do
      binary = "\x00\x01\x02\x03"
      expect(type.cast(binary)).to eq(binary)
    end

    it 'escapes binary data when serializing' do
      binary = "hello\x00world"
      expect(type.serialize(binary)).to eq("'hello\\0world'")
    end
  end
end
