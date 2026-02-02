# frozen_string_literal: true

require "spec_helper"

# Integration tests for HTTP compression
# Run with: CLICKHOUSE_TEST_INTEGRATION=true bundle exec rspec spec/integration/compression_spec.rb
RSpec.describe "HTTP Compression", :integration do
  let(:config) do
    ClickhouseRuby::Configuration.new.tap do |c|
      c.host = ENV.fetch("CLICKHOUSE_HOST", "localhost")
      c.port = ENV.fetch("CLICKHOUSE_PORT", 8123).to_i
      c.database = "default"
      c.compression = "gzip"
    end
  end

  let(:client) { ClickhouseRuby::Client.new(config) }

  before do
    # Create test table
    client.command("CREATE TABLE IF NOT EXISTS test_compression (id UInt64, name String) ENGINE = Memory")
  end

  after do
    # Clean up test table
    client.command("DROP TABLE IF EXISTS test_compression")
    client.close
  end

  describe "compressed SELECT queries" do
    it "executes SELECT with compression and returns correct data" do
      # Insert some data
      rows = [
        { id: 1, name: "test1" },
        { id: 2, name: "test2" },
        { id: 3, name: "test3" },
      ]
      client.insert("test_compression", rows)

      # Execute query with compression
      result = client.execute("SELECT * FROM test_compression ORDER BY id")

      expect(result.data.length).to eq(3)
      expect(result.data[0]).to eq([1, "test1"])
      expect(result.data[1]).to eq([2, "test2"])
      expect(result.data[2]).to eq([3, "test3"])
    end

    it "handles empty result sets with compression" do
      result = client.execute("SELECT * FROM test_compression WHERE id > 1000")

      expect(result.data.length).to eq(0)
    end

    it "handles large result sets with compression" do
      # Insert large dataset
      rows = (1..100).map { |i| { id: i, name: "test#{i}" } }
      client.insert("test_compression", rows)

      result = client.execute("SELECT * FROM test_compression WHERE id > 50")

      expect(result.data.length).to eq(50)
    end
  end

  describe "compressed INSERT operations" do
    it "executes INSERT with compressed body and succeeds" do
      rows = (1..10).map { |i| { id: i, name: "compressed#{i}" } }

      expect do
        client.insert("test_compression", rows)
      end.not_to raise_error

      result = client.execute("SELECT COUNT(*) as cnt FROM test_compression")
      expect(result.first["cnt"]).to eq(10)
    end

    it "handles large bulk INSERT with compression" do
      # Create a large dataset that will benefit from compression
      rows = (1..500).map { |i| { id: i, name: "large_test_#{i}" } }

      expect do
        client.insert("test_compression", rows)
      end.not_to raise_error

      result = client.execute("SELECT COUNT(*) as cnt FROM test_compression")
      expect(result.first["cnt"]).to eq(500)
    end
  end

  describe "compression disabled" do
    let(:config_no_compression) do
      ClickhouseRuby::Configuration.new.tap do |c|
        c.host = ENV.fetch("CLICKHOUSE_HOST", "localhost")
        c.port = ENV.fetch("CLICKHOUSE_PORT", 8123).to_i
        c.database = "default"
        c.compression = nil
      end
    end

    let(:client_no_compression) { ClickhouseRuby::Client.new(config_no_compression) }

    after do
      client_no_compression.close
    end

    it "works correctly without compression" do
      client_no_compression.command(
        "CREATE TABLE IF NOT EXISTS test_no_compression (id UInt64) ENGINE = Memory",
      )

      rows = [{ id: 1 }, { id: 2 }]
      client_no_compression.insert("test_no_compression", rows)

      result = client_no_compression.execute("SELECT COUNT(*) as cnt FROM test_no_compression")
      expect(result.first["cnt"]).to eq(2)

      client_no_compression.command("DROP TABLE IF EXISTS test_no_compression")
    end
  end

  describe "mixed compression scenarios" do
    it "switches between compressed and uncompressed queries" do
      # Insert with compression
      rows = (1..5).map { |i| { id: i, name: "mixed#{i}" } }
      client.insert("test_compression", rows)

      # Query with compression
      result1 = client.execute("SELECT COUNT(*) as cnt FROM test_compression")
      expect(result1.first["cnt"]).to eq(5)

      # Switch to non-compressed client
      config_no_compression = ClickhouseRuby::Configuration.new.tap do |c|
        c.host = ENV.fetch("CLICKHOUSE_HOST", "localhost")
        c.port = ENV.fetch("CLICKHOUSE_PORT", 8123).to_i
        c.database = "default"
        c.compression = nil
      end
      client_no_compression = ClickhouseRuby::Client.new(config_no_compression)

      # Query without compression
      result2 = client_no_compression.execute("SELECT COUNT(*) as cnt FROM test_compression")
      expect(result2.first["cnt"]).to eq(5)

      client_no_compression.close
    end
  end
end
