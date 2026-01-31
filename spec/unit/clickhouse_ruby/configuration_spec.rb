# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickhouseRuby::Configuration do
  subject(:config) { described_class.new }

  describe 'default values' do
    it 'has localhost as default host' do
      expect(config.host).to eq('localhost')
    end

    it 'has 8123 as default port' do
      expect(config.port).to eq(8123)
    end

    it 'has default as default database' do
      expect(config.database).to eq('default')
    end

    it 'has nil username by default' do
      expect(config.username).to be_nil
    end

    it 'has nil password by default' do
      expect(config.password).to be_nil
    end

    it 'has ssl disabled by default' do
      expect(config.ssl).to be false
    end

    # SECURITY: SSL verification must be enabled by default
    it 'has ssl_verify enabled by default' do
      expect(config.ssl_verify).to be true
    end

    it 'has nil ssl_ca_path by default' do
      expect(config.ssl_ca_path).to be_nil
    end

    it 'has 10 second connect_timeout' do
      expect(config.connect_timeout).to eq(10)
    end

    it 'has 60 second read_timeout' do
      expect(config.read_timeout).to eq(60)
    end

    it 'has 60 second write_timeout' do
      expect(config.write_timeout).to eq(60)
    end

    it 'has pool_size of 5' do
      expect(config.pool_size).to eq(5)
    end

    it 'has pool_timeout of 5' do
      expect(config.pool_timeout).to eq(5)
    end

    it 'has nil logger by default' do
      expect(config.logger).to be_nil
    end

    it 'has info log_level by default' do
      expect(config.log_level).to eq(:info)
    end

    it 'has empty default_settings' do
      expect(config.default_settings).to eq({})
    end
  end

  describe 'attribute setters' do
    it 'allows setting host' do
      config.host = 'clickhouse.example.com'
      expect(config.host).to eq('clickhouse.example.com')
    end

    it 'allows setting port' do
      config.port = 8443
      expect(config.port).to eq(8443)
    end

    it 'allows setting database' do
      config.database = 'analytics'
      expect(config.database).to eq('analytics')
    end

    it 'allows setting credentials' do
      config.username = 'admin'
      config.password = 'secret'
      expect(config.username).to eq('admin')
      expect(config.password).to eq('secret')
    end

    it 'allows setting ssl options' do
      config.ssl = true
      config.ssl_verify = false
      config.ssl_ca_path = '/path/to/ca.crt'

      expect(config.ssl).to be true
      expect(config.ssl_verify).to be false
      expect(config.ssl_ca_path).to eq('/path/to/ca.crt')
    end

    it 'allows setting timeouts' do
      config.connect_timeout = 5
      config.read_timeout = 30
      config.write_timeout = 30

      expect(config.connect_timeout).to eq(5)
      expect(config.read_timeout).to eq(30)
      expect(config.write_timeout).to eq(30)
    end

    it 'allows setting pool options' do
      config.pool_size = 10
      config.pool_timeout = 10

      expect(config.pool_size).to eq(10)
      expect(config.pool_timeout).to eq(10)
    end

    it 'allows setting logger' do
      logger = Logger.new($stdout)
      config.logger = logger
      config.log_level = :debug

      expect(config.logger).to eq(logger)
      expect(config.log_level).to eq(:debug)
    end

    it 'allows setting default_settings' do
      config.default_settings = { max_threads: 4 }
      expect(config.default_settings).to eq({ max_threads: 4 })
    end
  end

  describe '#base_url' do
    it 'returns http URL by default' do
      expect(config.base_url).to eq('http://localhost:8123')
    end

    it 'returns https URL when ssl is enabled' do
      config.ssl = true
      expect(config.base_url).to eq('https://localhost:8123')
    end

    it 'includes custom host and port' do
      config.host = 'clickhouse.example.com'
      config.port = 8443
      config.ssl = true
      expect(config.base_url).to eq('https://clickhouse.example.com:8443')
    end
  end

  describe '#use_ssl?' do
    context 'when ssl is explicitly set' do
      it 'returns true when ssl is true' do
        config.ssl = true
        expect(config.use_ssl?).to be true
      end

      it 'returns false when ssl is false' do
        config.ssl = false
        expect(config.use_ssl?).to be false
      end
    end

    context 'auto-detection based on port' do
      it 'returns true for port 8443' do
        config.ssl = nil
        config.port = 8443
        expect(config.use_ssl?).to be true
      end

      it 'returns true for port 443' do
        config.ssl = nil
        config.port = 443
        expect(config.use_ssl?).to be true
      end

      it 'returns false for port 8123' do
        config.ssl = nil
        config.port = 8123
        expect(config.use_ssl?).to be false
      end

      it 'returns false for port 9000' do
        config.ssl = nil
        config.port = 9000
        expect(config.use_ssl?).to be false
      end
    end

    context 'explicit ssl setting overrides auto-detection' do
      it 'respects ssl=false on port 8443' do
        config.ssl = false
        config.port = 8443
        expect(config.use_ssl?).to be false
      end

      it 'respects ssl=true on port 8123' do
        config.ssl = true
        config.port = 8123
        expect(config.use_ssl?).to be true
      end
    end
  end

  describe '#to_connection_options' do
    it 'returns hash with all connection settings' do
      config.host = 'clickhouse.example.com'
      config.port = 8443
      config.database = 'analytics'
      config.username = 'admin'
      config.password = 'secret'
      config.ssl = true
      config.ssl_verify = true
      config.ssl_ca_path = '/path/to/ca.crt'
      config.connect_timeout = 5
      config.read_timeout = 30
      config.write_timeout = 30

      options = config.to_connection_options

      expect(options[:host]).to eq('clickhouse.example.com')
      expect(options[:port]).to eq(8443)
      expect(options[:database]).to eq('analytics')
      expect(options[:username]).to eq('admin')
      expect(options[:password]).to eq('secret')
      expect(options[:use_ssl]).to be true
      expect(options[:ssl_verify]).to be true
      expect(options[:ssl_ca_path]).to eq('/path/to/ca.crt')
      expect(options[:connect_timeout]).to eq(5)
      expect(options[:read_timeout]).to eq(30)
      expect(options[:write_timeout]).to eq(30)
    end
  end

  describe '#dup' do
    it 'creates an independent copy' do
      config.host = 'original.example.com'
      config.database = 'original_db'

      copy = config.dup
      copy.host = 'copy.example.com'
      copy.database = 'copy_db'

      expect(config.host).to eq('original.example.com')
      expect(config.database).to eq('original_db')
      expect(copy.host).to eq('copy.example.com')
      expect(copy.database).to eq('copy_db')
    end

    it 'duplicates nested objects' do
      config.default_settings = { max_threads: 4 }

      copy = config.dup
      copy.default_settings[:max_threads] = 8

      expect(config.default_settings[:max_threads]).to eq(4)
      expect(copy.default_settings[:max_threads]).to eq(8)
    end
  end

  describe '#validate!' do
    context 'with valid configuration' do
      it 'returns true' do
        expect(config.validate!).to be true
      end
    end

    context 'with invalid host' do
      it 'raises ConfigurationError for nil host' do
        config.host = nil
        expect { config.validate! }.to raise_error(ClickhouseRuby::ConfigurationError, /host is required/)
      end

      it 'raises ConfigurationError for empty host' do
        config.host = ''
        expect { config.validate! }.to raise_error(ClickhouseRuby::ConfigurationError, /host is required/)
      end
    end

    context 'with invalid port' do
      it 'raises ConfigurationError for non-integer port' do
        config.port = 'invalid'
        expect { config.validate! }.to raise_error(ClickhouseRuby::ConfigurationError, /port must be a positive integer/)
      end

      it 'raises ConfigurationError for negative port' do
        config.port = -1
        expect { config.validate! }.to raise_error(ClickhouseRuby::ConfigurationError, /port must be a positive integer/)
      end

      it 'raises ConfigurationError for zero port' do
        config.port = 0
        expect { config.validate! }.to raise_error(ClickhouseRuby::ConfigurationError, /port must be a positive integer/)
      end
    end

    context 'with invalid database' do
      it 'raises ConfigurationError for nil database' do
        config.database = nil
        expect { config.validate! }.to raise_error(ClickhouseRuby::ConfigurationError, /database is required/)
      end

      it 'raises ConfigurationError for empty database' do
        config.database = ''
        expect { config.validate! }.to raise_error(ClickhouseRuby::ConfigurationError, /database is required/)
      end
    end

    context 'with invalid pool_size' do
      it 'raises ConfigurationError for zero pool_size' do
        config.pool_size = 0
        expect { config.validate! }.to raise_error(ClickhouseRuby::ConfigurationError, /pool_size must be at least 1/)
      end

      it 'raises ConfigurationError for negative pool_size' do
        config.pool_size = -1
        expect { config.validate! }.to raise_error(ClickhouseRuby::ConfigurationError, /pool_size must be at least 1/)
      end
    end
  end

  describe 'ClickhouseRuby.configure integration' do
    it 'yields the configuration object' do
      ClickhouseRuby.configure do |c|
        expect(c).to be_a(described_class)
      end
    end

    it 'allows setting configuration via block' do
      ClickhouseRuby.configure do |c|
        c.host = 'configured.example.com'
        c.port = 9000
        c.database = 'configured_db'
      end

      expect(ClickhouseRuby.configuration.host).to eq('configured.example.com')
      expect(ClickhouseRuby.configuration.port).to eq(9000)
      expect(ClickhouseRuby.configuration.database).to eq('configured_db')
    end

    it 'preserves configuration across calls' do
      ClickhouseRuby.configure { |c| c.host = 'first.example.com' }
      ClickhouseRuby.configure { |c| c.database = 'second_db' }

      expect(ClickhouseRuby.configuration.host).to eq('first.example.com')
      expect(ClickhouseRuby.configuration.database).to eq('second_db')
    end
  end

  describe 'ClickhouseRuby.reset_configuration!' do
    it 'resets to defaults' do
      ClickhouseRuby.configure do |c|
        c.host = 'custom.example.com'
        c.port = 9000
      end

      ClickhouseRuby.reset_configuration!

      expect(ClickhouseRuby.configuration.host).to eq('localhost')
      expect(ClickhouseRuby.configuration.port).to eq(8123)
    end
  end
end
