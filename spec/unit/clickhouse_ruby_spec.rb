# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickhouseRuby do
  describe 'VERSION' do
    it 'has a version number' do
      expect(ClickhouseRuby::VERSION).not_to be_nil
    end

    it 'follows semantic versioning format' do
      expect(ClickhouseRuby::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe '.configuration' do
    it 'returns a Configuration object' do
      expect(described_class.configuration).to be_a(ClickhouseRuby::Configuration)
    end

    it 'returns the same instance on multiple calls' do
      expect(described_class.configuration).to equal(described_class.configuration)
    end
  end

  describe '.configure' do
    it 'yields the configuration object' do
      yielded = nil
      described_class.configure { |c| yielded = c }
      expect(yielded).to be_a(ClickhouseRuby::Configuration)
    end

    it 'returns the configuration object' do
      result = described_class.configure { |c| c.host = 'test' }
      expect(result).to be_a(ClickhouseRuby::Configuration)
    end

    it 'allows chaining configuration' do
      described_class.configure do |config|
        config.host = 'example.com'
        config.port = 8443
        config.ssl = true
      end

      expect(described_class.configuration.host).to eq('example.com')
      expect(described_class.configuration.port).to eq(8443)
      expect(described_class.configuration.ssl).to be true
    end
  end

  describe '.reset_configuration!' do
    it 'creates a new configuration instance' do
      old_config = described_class.configuration
      described_class.reset_configuration!
      expect(described_class.configuration).not_to equal(old_config)
    end

    it 'resets configuration to defaults' do
      described_class.configure { |c| c.host = 'custom.example.com' }
      described_class.reset_configuration!
      expect(described_class.configuration.host).to eq('localhost')
    end
  end

  describe '.client' do
    it 'returns a Client instance' do
      expect(described_class.client).to be_a(ClickhouseRuby::Client)
    end

    it 'creates client with global configuration' do
      described_class.configure { |c| c.host = 'test.example.com' }
      # The client should use the configured host
      # We can't directly test this without accessing private state,
      # but we verify it creates successfully
      expect { described_class.client }.not_to raise_error
    end
  end

  describe 'convenience methods' do
    # These methods delegate to a client instance

    describe '.execute' do
      it 'is defined' do
        expect(described_class).to respond_to(:execute)
      end
    end

    describe '.insert' do
      it 'is defined' do
        expect(described_class).to respond_to(:insert)
      end
    end
  end

  describe 'error class hierarchy' do
    it 'defines Error as base class' do
      expect(ClickhouseRuby::Error.superclass).to eq(StandardError)
    end

    it 'defines connection errors' do
      expect(ClickhouseRuby::ConnectionError.superclass).to eq(ClickhouseRuby::Error)
      expect(ClickhouseRuby::ConnectionNotEstablished.superclass).to eq(ClickhouseRuby::ConnectionError)
      expect(ClickhouseRuby::ConnectionTimeout.superclass).to eq(ClickhouseRuby::ConnectionError)
      expect(ClickhouseRuby::SSLError.superclass).to eq(ClickhouseRuby::ConnectionError)
    end

    it 'defines query errors' do
      expect(ClickhouseRuby::QueryError.superclass).to eq(ClickhouseRuby::Error)
      expect(ClickhouseRuby::SyntaxError.superclass).to eq(ClickhouseRuby::QueryError)
      expect(ClickhouseRuby::UnknownTable.superclass).to eq(ClickhouseRuby::QueryError)
    end

    it 'defines type cast errors' do
      expect(ClickhouseRuby::TypeCastError.superclass).to eq(ClickhouseRuby::Error)
    end
  end

  describe 'Types module' do
    it 'provides lookup method' do
      expect(ClickhouseRuby::Types).to respond_to(:lookup)
    end

    it 'provides parse method' do
      expect(ClickhouseRuby::Types).to respond_to(:parse)
    end

    it 'provides reset! method' do
      expect(ClickhouseRuby::Types).to respond_to(:reset!)
    end
  end
end
