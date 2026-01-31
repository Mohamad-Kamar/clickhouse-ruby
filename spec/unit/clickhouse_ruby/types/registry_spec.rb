# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickhouseRuby::Types::Registry do
  subject(:registry) { described_class.new }

  describe '#initialize' do
    it 'creates an empty registry' do
      # An empty registry has no types registered, so lookup returns a Base type
      # (the registry falls back to Base for unknown types)
      result = registry.lookup('String')
      expect(result).to be_a(ClickhouseRuby::Types::Base)
      expect(result.name).to eq('String')
    end
  end

  describe '#register' do
    it 'registers a type class' do
      registry.register('TestType', ClickhouseRuby::Types::Base)
      type = registry.lookup('TestType')
      expect(type).to be_a(ClickhouseRuby::Types::Base)
      expect(type.name).to eq('TestType')
    end

    it 'allows overwriting registered types' do
      registry.register('TestType', ClickhouseRuby::Types::Base)
      registry.register('TestType', ClickhouseRuby::Types::Integer)
      type = registry.lookup('TestType')
      expect(type).to be_a(ClickhouseRuby::Types::Integer)
    end
  end

  describe '#register_defaults' do
    before { registry.register_defaults }

    describe 'integer types' do
      %w[Int8 Int16 Int32 Int64 Int128 Int256 UInt8 UInt16 UInt32 UInt64 UInt128 UInt256].each do |type_name|
        it "registers #{type_name}" do
          type = registry.lookup(type_name)
          expect(type).to be_a(ClickhouseRuby::Types::Integer)
          expect(type.name).to eq(type_name)
        end
      end
    end

    describe 'float types' do
      %w[Float32 Float64].each do |type_name|
        it "registers #{type_name}" do
          type = registry.lookup(type_name)
          expect(type).to be_a(ClickhouseRuby::Types::Float)
          expect(type.name).to eq(type_name)
        end
      end
    end

    describe 'string types' do
      %w[String FixedString].each do |type_name|
        it "registers #{type_name}" do
          type = registry.lookup(type_name)
          expect(type).to be_a(ClickhouseRuby::Types::String)
          expect(type.name).to eq(type_name)
        end
      end
    end

    describe 'date/time types' do
      %w[Date Date32 DateTime DateTime64].each do |type_name|
        it "registers #{type_name}" do
          type = registry.lookup(type_name)
          expect(type).to be_a(ClickhouseRuby::Types::DateTime)
          expect(type.name).to eq(type_name)
        end
      end
    end

    describe 'other basic types' do
      it 'registers UUID' do
        type = registry.lookup('UUID')
        expect(type).to be_a(ClickhouseRuby::Types::UUID)
      end

      it 'registers Bool' do
        type = registry.lookup('Bool')
        expect(type).to be_a(ClickhouseRuby::Types::Boolean)
      end
    end

    describe 'complex types' do
      it 'registers Array' do
        type = registry.lookup('Array(Int32)')
        expect(type).to be_a(ClickhouseRuby::Types::Array)
      end

      it 'registers Map' do
        type = registry.lookup('Map(String, Int32)')
        expect(type).to be_a(ClickhouseRuby::Types::Map)
      end

      it 'registers Tuple' do
        type = registry.lookup('Tuple(String, Int32)')
        expect(type).to be_a(ClickhouseRuby::Types::Tuple)
      end

      it 'registers Nullable' do
        type = registry.lookup('Nullable(String)')
        expect(type).to be_a(ClickhouseRuby::Types::Nullable)
      end

      it 'registers LowCardinality' do
        type = registry.lookup('LowCardinality(String)')
        expect(type.name).to eq('LowCardinality')
      end
    end
  end

  describe '#lookup' do
    before { registry.register_defaults }

    it 'returns type instance for simple types' do
      type = registry.lookup('String')
      expect(type).to be_a(ClickhouseRuby::Types::String)
    end

    it 'returns type instance for parameterized types' do
      type = registry.lookup('Array(Int32)')
      expect(type).to be_a(ClickhouseRuby::Types::Array)
      expect(type.element_type).to be_a(ClickhouseRuby::Types::Integer)
    end

    it 'returns type instance for nested types' do
      type = registry.lookup('Array(Nullable(String))')
      expect(type).to be_a(ClickhouseRuby::Types::Array)
      expect(type.element_type).to be_a(ClickhouseRuby::Types::Nullable)
      expect(type.element_type.element_type).to be_a(ClickhouseRuby::Types::String)
    end

    it 'returns base type for unknown types' do
      type = registry.lookup('UnknownType')
      expect(type).to be_a(ClickhouseRuby::Types::Base)
      expect(type.name).to eq('UnknownType')
    end

    it 'caches lookup results' do
      type1 = registry.lookup('Int32')
      type2 = registry.lookup('Int32')
      expect(type1).to equal(type2)  # Same object
    end

    it 'invalidates cache when registering new type' do
      registry.lookup('Int32')
      registry.register('Int32', ClickhouseRuby::Types::Base)
      type = registry.lookup('Int32')
      expect(type).to be_a(ClickhouseRuby::Types::Base)
      expect(type).not_to be_a(ClickhouseRuby::Types::Integer)
    end

    describe 'complex nested types' do
      it 'handles Array(Tuple(String, UInt64))' do
        type = registry.lookup('Array(Tuple(String, UInt64))')
        expect(type).to be_a(ClickhouseRuby::Types::Array)
        expect(type.element_type).to be_a(ClickhouseRuby::Types::Tuple)
        expect(type.element_type.element_types.length).to eq(2)
        expect(type.element_type.element_types[0]).to be_a(ClickhouseRuby::Types::String)
        expect(type.element_type.element_types[1]).to be_a(ClickhouseRuby::Types::Integer)
      end

      it 'handles Map(String, Array(Nullable(Int64)))' do
        type = registry.lookup('Map(String, Array(Nullable(Int64)))')
        expect(type).to be_a(ClickhouseRuby::Types::Map)
        expect(type.key_type).to be_a(ClickhouseRuby::Types::String)
        expect(type.value_type).to be_a(ClickhouseRuby::Types::Array)
        expect(type.value_type.element_type).to be_a(ClickhouseRuby::Types::Nullable)
        expect(type.value_type.element_type.element_type).to be_a(ClickhouseRuby::Types::Integer)
      end

      it 'handles Tuple(String, Map(String, Int32), Array(UInt64))' do
        type = registry.lookup('Tuple(String, Map(String, Int32), Array(UInt64))')
        expect(type).to be_a(ClickhouseRuby::Types::Tuple)
        expect(type.element_types.length).to eq(3)
        expect(type.element_types[0]).to be_a(ClickhouseRuby::Types::String)
        expect(type.element_types[1]).to be_a(ClickhouseRuby::Types::Map)
        expect(type.element_types[2]).to be_a(ClickhouseRuby::Types::Array)
      end

      it 'handles Nullable(LowCardinality(String))' do
        type = registry.lookup('Nullable(LowCardinality(String))')
        expect(type).to be_a(ClickhouseRuby::Types::Nullable)
        expect(type.element_type.name).to eq('LowCardinality')
      end
    end
  end

  describe 'type building' do
    before { registry.register_defaults }

    describe 'wrapper types (single argument)' do
      it 'correctly builds Array with element_type' do
        type = registry.lookup('Array(Int32)')
        expect(type.element_type).to be_a(ClickhouseRuby::Types::Integer)
        expect(type.element_type.name).to eq('Int32')
      end

      it 'correctly builds Nullable with element_type' do
        type = registry.lookup('Nullable(String)')
        expect(type.element_type).to be_a(ClickhouseRuby::Types::String)
      end
    end

    describe 'multi-argument types' do
      it 'correctly builds Map with key_type and value_type' do
        type = registry.lookup('Map(String, Int64)')
        expect(type.key_type).to be_a(ClickhouseRuby::Types::String)
        expect(type.value_type).to be_a(ClickhouseRuby::Types::Integer)
        expect(type.value_type.name).to eq('Int64')
      end

      it 'correctly builds Tuple with element_types' do
        type = registry.lookup('Tuple(String, Int32, Float64)')
        expect(type.element_types.length).to eq(3)
        expect(type.element_types[0]).to be_a(ClickhouseRuby::Types::String)
        expect(type.element_types[1]).to be_a(ClickhouseRuby::Types::Integer)
        expect(type.element_types[2]).to be_a(ClickhouseRuby::Types::Float)
      end
    end
  end
end

RSpec.describe 'ClickhouseRuby::Types module integration' do
  before { ClickhouseRuby::Types.reset! }

  describe '.registry' do
    it 'returns a registry with defaults registered' do
      registry = ClickhouseRuby::Types.registry
      expect(registry).to be_a(ClickhouseRuby::Types::Registry)

      type = registry.lookup('String')
      expect(type).to be_a(ClickhouseRuby::Types::String)
    end

    it 'returns the same registry instance' do
      expect(ClickhouseRuby::Types.registry).to equal(ClickhouseRuby::Types.registry)
    end
  end

  describe '.lookup' do
    it 'delegates to registry' do
      type = ClickhouseRuby::Types.lookup('Int32')
      expect(type).to be_a(ClickhouseRuby::Types::Integer)
    end

    it 'handles complex types' do
      type = ClickhouseRuby::Types.lookup('Array(Tuple(String, UInt64))')
      expect(type).to be_a(ClickhouseRuby::Types::Array)
    end
  end

  describe '.parse' do
    it 'returns AST for type string' do
      ast = ClickhouseRuby::Types.parse('Array(String)')
      expect(ast).to eq({
        type: 'Array',
        args: [{ type: 'String' }]
      })
    end
  end

  describe '.reset!' do
    it 'resets the registry' do
      registry1 = ClickhouseRuby::Types.registry
      ClickhouseRuby::Types.reset!
      registry2 = ClickhouseRuby::Types.registry
      expect(registry1).not_to equal(registry2)
    end
  end
end
