# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Client do
  let(:config) do
    ClickhouseRuby::Configuration.new.tap do |c|
      c.host = "localhost"
      c.port = 8123
      c.database = "default"
    end
  end

  let(:mock_pool) { instance_double(ClickhouseRuby::ConnectionPool) }
  let(:mock_connection) { instance_double(ClickhouseRuby::Connection) }

  before do
    allow(ClickhouseRuby::ConnectionPool).to receive(:new).and_return(mock_pool)
  end

  describe "#initialize" do
    it "creates a new client with valid configuration" do
      expect { described_class.new(config) }.not_to raise_error
    end

    it "validates the configuration" do
      invalid_config = ClickhouseRuby::Configuration.new
      invalid_config.host = nil

      expect { described_class.new(invalid_config) }.to raise_error(ClickhouseRuby::ConfigurationError)
    end

    it "creates a connection pool" do
      expect(ClickhouseRuby::ConnectionPool).to receive(:new).with(config)
      described_class.new(config)
    end

    it "stores the configuration" do
      client = described_class.new(config)
      expect(client.config).to eq(config)
    end

    it "stores the pool" do
      client = described_class.new(config)
      expect(client.pool).to eq(mock_pool)
    end
  end

  describe "#execute" do
    let(:client) { described_class.new(config) }
    let(:mock_response) do
      instance_double(Net::HTTPResponse, code: "200", body: '{"meta":[],"data":[],"statistics":{}}')
    end

    before do
      allow(mock_pool).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:post).and_return(mock_response)
    end

    it "executes a query through the pool" do
      expect(mock_pool).to receive(:with_connection).and_yield(mock_connection)
      client.execute("SELECT 1")
    end

    it "appends FORMAT to the query" do
      expect(mock_connection).to receive(:post) do |_path, body|
        expect(body).to include("FORMAT JSONCompact")
        mock_response
      end
      client.execute("SELECT 1")
    end

    it "returns a Result object" do
      result = client.execute("SELECT 1")
      expect(result).to be_a(ClickhouseRuby::Result)
    end

    context "when query fails" do
      let(:error_response) do
        instance_double(Net::HTTPResponse, code: "400", body: "Code: 62. DB::Exception: Syntax error")
      end

      before do
        allow(mock_connection).to receive(:post).and_return(error_response)
      end

      it "raises QueryError" do
        expect { client.execute("INVALID SQL") }.to raise_error(ClickhouseRuby::QueryError)
      end
    end

    context "with custom settings" do
      it "includes settings in query parameters" do
        expect(mock_connection).to receive(:post) do |path, _body|
          expect(path).to include("max_execution_time=120")
          mock_response
        end
        client.execute("SELECT 1", settings: { max_execution_time: 120 })
      end
    end
  end

  describe "#command" do
    let(:client) { described_class.new(config) }
    let(:mock_response) { instance_double(Net::HTTPResponse, code: "200", body: "") }

    before do
      allow(mock_pool).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:post).and_return(mock_response)
    end

    it "returns true on success" do
      result = client.command("CREATE TABLE test (id UInt64) ENGINE = Memory")
      expect(result).to be true
    end

    context "when command fails" do
      let(:error_response) do
        instance_double(Net::HTTPResponse, code: "400", body: "Code: 60. Table already exists")
      end

      before do
        allow(mock_connection).to receive(:post).and_return(error_response)
      end

      it "raises QueryError" do
        expect { client.command("CREATE TABLE test (id UInt64)") }.to raise_error(ClickhouseRuby::QueryError)
      end
    end
  end

  describe "#insert" do
    let(:client) { described_class.new(config) }
    let(:mock_response) { instance_double(Net::HTTPResponse, code: "200", body: "") }

    before do
      allow(mock_pool).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:post).and_return(mock_response)
    end

    it "inserts rows successfully" do
      rows = [{ id: 1, name: "test" }, { id: 2, name: "test2" }]
      result = client.insert("events", rows)
      expect(result).to be true
    end

    it "raises ArgumentError for empty rows" do
      expect { client.insert("events", []) }.to raise_error(ArgumentError, "rows cannot be empty")
    end

    it "raises ArgumentError for nil rows" do
      expect { client.insert("events", nil) }.to raise_error(ArgumentError, "rows cannot be empty")
    end

    it "infers columns from the first row" do
      rows = [{ id: 1, name: "test" }]
      expect(mock_connection).to receive(:post) do |path, _body, _headers|
        expect(path).to include("INSERT")
        expect(path).to include("id")
        expect(path).to include("name")
        mock_response
      end
      client.insert("events", rows)
    end

    it "uses explicit columns when provided" do
      rows = [{ id: 1, name: "test", extra: "ignored" }]
      expect(mock_connection).to receive(:post) do |path, _body, _headers|
        expect(path).to include("id")
        expect(path).not_to include("extra")
        mock_response
      end
      client.insert("events", rows, columns: ["id"])
    end

    it "serializes Time values" do
      rows = [{ id: 1, created_at: Time.new(2024, 1, 15, 10, 30, 0) }]
      expect(mock_connection).to receive(:post) do |_path, body, _headers|
        expect(body).to include("2024-01-15 10:30:00")
        mock_response
      end
      client.insert("events", rows)
    end

    it "serializes Date values" do
      rows = [{ id: 1, date: Date.new(2024, 1, 15) }]
      expect(mock_connection).to receive(:post) do |_path, body, _headers|
        expect(body).to include("2024-01-15")
        mock_response
      end
      client.insert("events", rows)
    end
  end

  describe "#ping" do
    let(:client) { described_class.new(config) }

    context "when server is reachable" do
      before do
        allow(mock_pool).to receive(:with_connection).and_yield(mock_connection)
        allow(mock_connection).to receive(:ping).and_return(true)
      end

      it "returns true" do
        expect(client.ping).to be true
      end
    end

    context "when server is unreachable" do
      before do
        allow(mock_pool).to receive(:with_connection).and_yield(mock_connection)
        allow(mock_connection).to receive(:ping).and_return(false)
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when connection error occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(ClickhouseRuby::ConnectionError.new("Connection failed"))
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when connection timeout occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(ClickhouseRuby::ConnectionTimeout.new("Timeout"))
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when PoolTimeout occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(ClickhouseRuby::PoolTimeout.new("Pool exhausted"))
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when Errno::ECONNREFUSED occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(Errno::ECONNREFUSED)
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when Errno::ENETUNREACH occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(Errno::ENETUNREACH)
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when Errno::ETIMEDOUT occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(Errno::ETIMEDOUT)
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when Errno::ENETDOWN occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(Errno::ENETDOWN)
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when SocketError occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(SocketError.new("getaddrinfo: Name or service not known"))
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when Net::OpenTimeout occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(Net::OpenTimeout)
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when Net::ReadTimeout occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(Net::ReadTimeout)
      end

      it "returns false" do
        expect(client.ping).to be false
      end
    end

    context "when programming error occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(NoMethodError.new("undefined method"))
      end

      it "raises the error instead of returning false" do
        expect { client.ping }.to raise_error(NoMethodError)
      end
    end

    context "when ArgumentError occurs" do
      before do
        allow(mock_pool).to receive(:with_connection).and_raise(ArgumentError.new("wrong number of arguments"))
      end

      it "raises the error instead of returning false" do
        expect { client.ping }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#server_version" do
    let(:client) { described_class.new(config) }
    let(:mock_response) do
      instance_double(Net::HTTPResponse, code: "200",
                                         body: '{"meta":[{"name":"version","type":"String"}],"data":[["24.1.1.1"]],"statistics":{}}',)
    end

    before do
      allow(mock_pool).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:post).and_return(mock_response)
    end

    it "returns the server version string" do
      expect(client.server_version).to eq("24.1.1.1")
    end
  end

  describe "#close" do
    let(:client) { described_class.new(config) }

    it "shuts down the pool" do
      expect(mock_pool).to receive(:shutdown)
      client.close
    end

    it "is aliased to disconnect" do
      expect(mock_pool).to receive(:shutdown)
      client.disconnect
    end
  end

  describe "#pool_stats" do
    let(:client) { described_class.new(config) }
    let(:stats) { { size: 5, available: 3, in_use: 2 } }

    before do
      allow(mock_pool).to receive(:stats).and_return(stats)
    end

    it "returns pool statistics" do
      expect(client.pool_stats).to eq(stats)
    end
  end

  describe "enable_http_compression query parameter" do
    let(:client) { described_class.new(config) }
    let(:mock_response) do
      instance_double(Net::HTTPResponse, code: "200", body: '{"meta":[],"data":[],"statistics":{}}')
    end

    before do
      allow(mock_pool).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:post).and_return(mock_response)
    end

    context "when compression is disabled" do
      it "does not include enable_http_compression parameter" do
        config.compression = nil
        expect(mock_connection).to receive(:post) do |path, _body|
          expect(path).not_to include("enable_http_compression")
          mock_response
        end
        client.execute("SELECT 1")
      end
    end

    context "when compression is enabled" do
      it "includes enable_http_compression=1 parameter" do
        config.compression = "gzip"
        expect(mock_connection).to receive(:post) do |path, _body|
          expect(path).to include("enable_http_compression=1")
          mock_response
        end
        client.execute("SELECT 1")
      end

      it "includes parameter in command" do
        config.compression = "gzip"
        expect(mock_connection).to receive(:post) do |path, _body|
          expect(path).to include("enable_http_compression=1")
          mock_response
        end
        client.command("CREATE TABLE test (id UInt64) ENGINE = Memory")
      end
    end
  end

  describe "#stream_execute" do
    let(:client) { described_class.new(config) }

    it "creates a StreamingResult instance" do
      result = client.stream_execute("SELECT * FROM test")
      expect(result).to be_a(ClickhouseRuby::StreamingResult)
    end

    it "passes sql to StreamingResult" do
      sql = "SELECT * FROM test"
      result = client.stream_execute(sql)
      expect(result.instance_variable_get(:@sql)).to eq(sql)
    end

    it "passes compression setting to StreamingResult" do
      config.compression = "gzip"
      client_with_compression = described_class.new(config)
      result = client_with_compression.stream_execute("SELECT * FROM test")
      expect(result.instance_variable_get(:@compression)).to eq("gzip")
    end
  end

  describe "#each_row" do
    let(:client) { described_class.new(config) }

    it "streams rows with block" do
      rows = []
      stream_result = instance_double(ClickhouseRuby::StreamingResult)
      allow(ClickhouseRuby::StreamingResult).to receive(:new).and_return(stream_result)
      allow(stream_result).to receive(:each).and_yield(
        { "id" => 1 },
      ).and_yield(
        { "id" => 2 },
      )

      client.each_row("SELECT * FROM test") do |row|
        rows << row
      end

      expect(rows.size).to eq(2)
    end
  end

  describe "#retry integration" do
    let(:client) { described_class.new(config) }

    it "initializes retry_handler with config values" do
      expect(client.retry_handler).to be_a(ClickhouseRuby::RetryHandler)
      expect(client.retry_handler.max_attempts).to eq(config.max_retries)
      expect(client.retry_handler.initial_backoff).to eq(config.initial_backoff)
      expect(client.retry_handler.max_backoff).to eq(config.max_backoff)
      expect(client.retry_handler.multiplier).to eq(config.backoff_multiplier)
      expect(client.retry_handler.jitter).to eq(config.retry_jitter)
    end

    it "initializes retry handler with config" do
      client = described_class.new(config)

      # Verify retry handler is present and configured from config
      expect(client.retry_handler).to be_a(ClickhouseRuby::RetryHandler)
      expect(client.retry_handler.max_attempts).to eq(config.max_retries)
    end

    it "allows retry_handler configuration" do
      config.max_retries = 5
      config.initial_backoff = 0.5
      config.max_backoff = 60.0
      config.backoff_multiplier = 2.0
      config.retry_jitter = :full

      client = described_class.new(config)

      expect(client.retry_handler.max_attempts).to eq(5)
      expect(client.retry_handler.initial_backoff).to eq(0.5)
      expect(client.retry_handler.max_backoff).to eq(60.0)
      expect(client.retry_handler.multiplier).to eq(2.0)
      expect(client.retry_handler.jitter).to eq(:full)
    end
  end
end
