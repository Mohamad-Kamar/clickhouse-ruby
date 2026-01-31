# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickhouseRuby::Types::UUID do
  subject(:type) { described_class.new('UUID') }

  describe '#name' do
    it 'returns UUID' do
      expect(type.name).to eq('UUID')
    end
  end

  describe '#cast' do
    context 'from nil' do
      it 'returns nil' do
        expect(type.cast(nil)).to be_nil
      end
    end

    context 'with valid UUID formats' do
      it 'accepts standard UUID format' do
        uuid = '550e8400-e29b-41d4-a716-446655440000'
        expect(type.cast(uuid)).to eq(uuid)
      end

      it 'accepts uppercase UUID' do
        uuid = '550E8400-E29B-41D4-A716-446655440000'
        expect(type.cast(uuid)).to eq('550e8400-e29b-41d4-a716-446655440000')
      end

      it 'accepts UUID without hyphens' do
        expect(type.cast('550e8400e29b41d4a716446655440000')).to eq('550e8400-e29b-41d4-a716-446655440000')
      end

      it 'accepts UUID with braces' do
        expect(type.cast('{550e8400-e29b-41d4-a716-446655440000}')).to eq('550e8400-e29b-41d4-a716-446655440000')
      end

      it 'accepts UUID without hyphens and with braces' do
        expect(type.cast('{550e8400e29b41d4a716446655440000}')).to eq('550e8400-e29b-41d4-a716-446655440000')
      end

      it 'strips whitespace' do
        expect(type.cast('  550e8400-e29b-41d4-a716-446655440000  ')).to eq('550e8400-e29b-41d4-a716-446655440000')
      end
    end

    context 'with invalid UUID formats' do
      it 'raises TypeCastError for empty string' do
        expect { type.cast('') }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'raises TypeCastError for invalid format' do
        expect { type.cast('not-a-uuid') }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'raises TypeCastError for wrong length' do
        expect { type.cast('550e8400-e29b-41d4-a716') }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'raises TypeCastError for invalid characters' do
        expect { type.cast('550g8400-e29b-41d4-a716-446655440000') }.to raise_error(ClickhouseRuby::TypeCastError)
      end

      it 'includes error details' do
        expect { type.cast('invalid') }.to raise_error do |error|
          expect(error.from_type).to eq('String')
          expect(error.to_type).to eq('UUID')
          expect(error.value).to eq('invalid')
        end
      end
    end
  end

  describe '#deserialize' do
    context 'from nil' do
      it 'returns nil' do
        expect(type.deserialize(nil)).to be_nil
      end
    end

    context 'with valid UUID' do
      it 'normalizes standard format' do
        uuid = '550e8400-e29b-41d4-a716-446655440000'
        expect(type.deserialize(uuid)).to eq(uuid)
      end

      it 'normalizes uppercase to lowercase' do
        expect(type.deserialize('550E8400-E29B-41D4-A716-446655440000')).to eq('550e8400-e29b-41d4-a716-446655440000')
      end

      it 'adds hyphens when missing' do
        expect(type.deserialize('550e8400e29b41d4a716446655440000')).to eq('550e8400-e29b-41d4-a716-446655440000')
      end

      it 'removes braces' do
        expect(type.deserialize('{550e8400-e29b-41d4-a716-446655440000}')).to eq('550e8400-e29b-41d4-a716-446655440000')
      end
    end
  end

  describe '#serialize' do
    context 'from nil' do
      it 'returns NULL' do
        expect(type.serialize(nil)).to eq('NULL')
      end
    end

    context 'with valid UUID' do
      it 'quotes the UUID' do
        uuid = '550e8400-e29b-41d4-a716-446655440000'
        expect(type.serialize(uuid)).to eq("'550e8400-e29b-41d4-a716-446655440000'")
      end

      it 'normalizes before quoting' do
        expect(type.serialize('550E8400-E29B-41D4-A716-446655440000')).to eq("'550e8400-e29b-41d4-a716-446655440000'")
      end
    end
  end

  describe 'edge cases' do
    it 'handles nil UUID (all zeros)' do
      nil_uuid = '00000000-0000-0000-0000-000000000000'
      expect(type.cast(nil_uuid)).to eq(nil_uuid)
    end

    it 'handles max UUID (all f)' do
      max_uuid = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
      expect(type.cast(max_uuid)).to eq(max_uuid)
    end
  end
end
