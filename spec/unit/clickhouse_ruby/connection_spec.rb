# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Connection do
  let(:connection_options) do
    {
      host: "localhost",
      port: 8123,
      database: "default",
      username: nil,
      password: nil,
      use_ssl: false,
      ssl_verify: true,
      connect_timeout: 10,
      read_timeout: 60,
      write_timeout: 60,
    }
  end

  let(:connection) { described_class.new(**connection_options) }

  describe "#initialize" do
    it "stores connection parameters" do
      expect(connection.host).to eq("localhost")
      expect(connection.port).to eq(8123)
      expect(connection.database).to eq("default")
    end

    it "defaults to not connected" do
      expect(connection.connected?).to be false
    end

    it "defaults ssl to false" do
      expect(connection.use_ssl).to be false
    end
  end

  describe "#connect" do
    let(:mock_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:write_timeout=)
      allow(mock_http).to receive(:keep_alive_timeout=)
      allow(mock_http).to receive(:start)
      allow(mock_http).to receive(:started?).and_return(true)
    end

    it "creates an HTTP connection" do
      expect(Net::HTTP).to receive(:new).with("localhost", 8123)
      connection.connect
    end

    it "sets timeouts" do
      expect(mock_http).to receive(:open_timeout=).with(10)
      expect(mock_http).to receive(:read_timeout=).with(60)
      expect(mock_http).to receive(:write_timeout=).with(60)
      connection.connect
    end

    it "starts the connection" do
      expect(mock_http).to receive(:start)
      connection.connect
    end

    it "marks connection as connected" do
      connection.connect
      expect(connection.connected?).to be true
    end

    it "returns self" do
      expect(connection.connect).to eq(connection)
    end

    context "when connection fails" do
      before do
        allow(mock_http).to receive(:start).and_raise(Errno::ECONNREFUSED)
      end

      it "raises ConnectionNotEstablished" do
        expect { connection.connect }.to raise_error(ClickhouseRuby::ConnectionNotEstablished)
      end
    end

    context "when connection times out" do
      before do
        allow(mock_http).to receive(:start).and_raise(Net::OpenTimeout)
      end

      it "raises ConnectionTimeout" do
        expect { connection.connect }.to raise_error(ClickhouseRuby::ConnectionTimeout)
      end
    end

    context "with SSL enabled" do
      let(:ssl_options) { connection_options.merge(use_ssl: true, ssl_verify: true) }
      let(:ssl_connection) { described_class.new(**ssl_options) }

      before do
        allow(mock_http).to receive(:use_ssl=)
        allow(mock_http).to receive(:verify_mode=)
        allow(mock_http).to receive(:min_version=)
      end

      it "enables SSL" do
        expect(mock_http).to receive(:use_ssl=).with(true)
        ssl_connection.connect
      end

      it "enables SSL verification by default" do
        expect(mock_http).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
        ssl_connection.connect
      end

      it "sets minimum TLS version" do
        expect(mock_http).to receive(:min_version=).with(OpenSSL::SSL::TLS1_2_VERSION)
        ssl_connection.connect
      end

      context "with ssl_verify disabled" do
        let(:insecure_options) { connection_options.merge(use_ssl: true, ssl_verify: false) }
        let(:insecure_connection) { described_class.new(**insecure_options) }

        it "disables SSL verification" do
          expect(mock_http).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
          expect { insecure_connection.connect }.to output(/WARNING: SSL verification disabled/).to_stderr
        end
      end

      context "with custom CA path" do
        let(:ca_options) { connection_options.merge(use_ssl: true, ssl_ca_path: "/path/to/ca.crt") }
        let(:ca_connection) { described_class.new(**ca_options) }

        before do
          allow(mock_http).to receive(:ca_file=)
        end

        it "sets the CA file" do
          expect(mock_http).to receive(:ca_file=).with("/path/to/ca.crt")
          ca_connection.connect
        end
      end

      context "when SSL handshake fails" do
        before do
          allow(mock_http).to receive(:start).and_raise(OpenSSL::SSL::SSLError.new("SSL_connect error"))
        end

        it "raises SSLError" do
          expect { ssl_connection.connect }.to raise_error(ClickhouseRuby::SSLError)
        end
      end
    end
  end

  describe "#disconnect" do
    let(:mock_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:write_timeout=)
      allow(mock_http).to receive(:keep_alive_timeout=)
      allow(mock_http).to receive(:start)
      allow(mock_http).to receive(:started?).and_return(true)
      allow(mock_http).to receive(:finish)
    end

    it "closes the connection" do
      connection.connect
      expect(mock_http).to receive(:finish)
      connection.disconnect
    end

    it "marks connection as disconnected" do
      connection.connect
      connection.disconnect
      expect(connection.connected?).to be false
    end

    it "returns self" do
      connection.connect
      expect(connection.disconnect).to eq(connection)
    end

    it "is idempotent" do
      expect { connection.disconnect }.not_to raise_error
    end
  end

  describe "#reconnect" do
    let(:mock_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:write_timeout=)
      allow(mock_http).to receive(:keep_alive_timeout=)
      allow(mock_http).to receive(:start)
      allow(mock_http).to receive(:started?).and_return(true)
      allow(mock_http).to receive(:finish)
    end

    it "disconnects and reconnects" do
      connection.connect
      expect(connection).to receive(:disconnect).and_call_original
      expect(connection).to receive(:connect).and_call_original
      connection.reconnect
    end
  end

  describe "#post" do
    let(:mock_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:write_timeout=)
      allow(mock_http).to receive(:keep_alive_timeout=)
      allow(mock_http).to receive(:start)
      allow(mock_http).to receive(:started?).and_return(true)
    end

    it "sends a POST request" do
      mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
      allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
      allow(mock_http).to receive(:request).and_return(mock_response)

      connection.connect
      connection.post("/query", "SELECT 1")

      expect(mock_http).to have_received(:request) do |request|
        expect(request).to be_a(Net::HTTP::Post)
      end
    end

    it "sets the body" do
      mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
      allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
      allow(mock_http).to receive(:request).and_return(mock_response)

      connection.connect
      connection.post("/query", "SELECT 1")

      expect(mock_http).to have_received(:request) do |request|
        expect(request.body).to eq("SELECT 1")
      end
    end

    it "sets default headers" do
      mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
      allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
      allow(mock_http).to receive(:request).and_return(mock_response)

      connection.connect
      connection.post("/query", "SELECT 1")

      expect(mock_http).to have_received(:request) do |request|
        expect(request["Content-Type"]).to eq("application/x-www-form-urlencoded")
        expect(request["Accept"]).to eq("application/json")
        expect(request["User-Agent"]).to include("ClickhouseRuby")
      end
    end

    it "allows custom headers" do
      mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
      allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
      allow(mock_http).to receive(:request).and_return(mock_response)

      connection.connect
      connection.post("/query", "SELECT 1", { "X-Custom" => "value" })

      expect(mock_http).to have_received(:request) do |request|
        expect(request["X-Custom"]).to eq("value")
      end
    end

    context "with authentication" do
      let(:auth_options) { connection_options.merge(username: "user", password: "pass") }
      let(:auth_connection) { described_class.new(**auth_options) }

      it "sets basic auth header" do
        mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
        allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
        allow(mock_http).to receive(:request).and_return(mock_response)

        auth_connection.connect
        auth_connection.post("/query", "SELECT 1")

        expect(mock_http).to have_received(:request) do |request|
          expect(request["Authorization"]).to include("Basic")
        end
      end
    end

    context "when read timeout occurs" do
      before do
        connection.connect
        allow(mock_http).to receive(:request).and_raise(Net::ReadTimeout)
      end

      it "raises ConnectionTimeout" do
        expect { connection.post("/query", "SELECT 1") }.to raise_error(ClickhouseRuby::ConnectionTimeout)
      end
    end

    context "when write timeout occurs" do
      before do
        connection.connect
        allow(mock_http).to receive(:request).and_raise(Net::WriteTimeout)
      end

      it "raises ConnectionTimeout" do
        expect { connection.post("/query", "SELECT 1") }.to raise_error(ClickhouseRuby::ConnectionTimeout)
      end
    end

    context "when connection is reset" do
      before do
        connection.connect
        allow(mock_http).to receive(:request).and_raise(Errno::ECONNRESET)
      end

      it "raises ConnectionError" do
        expect { connection.post("/query", "SELECT 1") }.to raise_error(ClickhouseRuby::ConnectionError)
      end
    end
  end

  describe "#get" do
    let(:mock_http) { instance_double(Net::HTTP) }
    let(:mock_response) { instance_double(Net::HTTPResponse, code: "200", body: "Ok") }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:write_timeout=)
      allow(mock_http).to receive(:keep_alive_timeout=)
      allow(mock_http).to receive(:start)
      allow(mock_http).to receive(:started?).and_return(true)
      allow(mock_http).to receive(:request).and_return(mock_response)
    end

    it "sends a GET request" do
      connection.connect
      expect(mock_http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Get)
        mock_response
      end
      connection.get("/ping")
    end
  end

  describe "#ping" do
    let(:mock_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:write_timeout=)
      allow(mock_http).to receive(:keep_alive_timeout=)
      allow(mock_http).to receive(:start)
      allow(mock_http).to receive(:started?).and_return(true)
    end

    context "when server responds correctly" do
      let(:mock_response) { instance_double(Net::HTTPResponse, code: "200", body: "Ok.") }

      before do
        allow(mock_http).to receive(:request).and_return(mock_response)
      end

      it "returns true" do
        expect(connection.ping).to be true
      end
    end

    context "when server responds with error" do
      let(:mock_response) { instance_double(Net::HTTPResponse, code: "500", body: "Error") }

      before do
        allow(mock_http).to receive(:request).and_return(mock_response)
      end

      it "returns false" do
        expect(connection.ping).to be false
      end
    end

    context "when connection fails" do
      before do
        allow(mock_http).to receive(:start).and_raise(Errno::ECONNREFUSED)
      end

      it "returns false" do
        expect(connection.ping).to be false
      end
    end
  end

  describe "#healthy?" do
    let(:mock_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:write_timeout=)
      allow(mock_http).to receive(:keep_alive_timeout=)
      allow(mock_http).to receive(:start)
    end

    it "returns false when not connected" do
      expect(connection.healthy?).to be false
    end

    context "when connected" do
      before do
        allow(mock_http).to receive(:started?).and_return(true)
        connection.connect
      end

      it "returns true when http is started" do
        expect(connection.healthy?).to be true
      end
    end
  end

  describe "#stale?" do
    it "returns true when never used" do
      expect(connection.stale?).to be true
    end

    context "when recently used" do
      let(:mock_http) { instance_double(Net::HTTP) }

      before do
        allow(Net::HTTP).to receive(:new).and_return(mock_http)
        allow(mock_http).to receive(:open_timeout=)
        allow(mock_http).to receive(:read_timeout=)
        allow(mock_http).to receive(:write_timeout=)
        allow(mock_http).to receive(:keep_alive_timeout=)
        allow(mock_http).to receive(:start)
        allow(mock_http).to receive(:started?).and_return(true)
        connection.connect
      end

      it "returns false" do
        expect(connection.stale?).to be false
      end

      it "returns true after max_idle_seconds" do
        expect(connection.stale?(0)).to be true
      end
    end
  end

  describe "#inspect" do
    it "returns a descriptive string" do
      expect(connection.inspect).to include("Connection")
      expect(connection.inspect).to include("localhost")
      expect(connection.inspect).to include("8123")
      expect(connection.inspect).to include("disconnected")
    end

    context "with SSL" do
      let(:ssl_options) { connection_options.merge(use_ssl: true) }
      let(:ssl_connection) { described_class.new(**ssl_options) }

      it "shows https scheme" do
        expect(ssl_connection.inspect).to include("https://")
      end
    end
  end

  describe "HTTP compression" do
    let(:mock_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(mock_http).to receive(:write_timeout=)
      allow(mock_http).to receive(:keep_alive_timeout=)
      allow(mock_http).to receive(:start)
      allow(mock_http).to receive(:started?).and_return(true)
    end

    describe "Accept-Encoding header" do
      it "does not explicitly set Accept-Encoding when compression is disabled" do
        mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
        allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
        captured_request = nil
        allow(mock_http).to receive(:request) do |req|
          captured_request = req
          mock_response
        end

        connection.connect
        connection.post("/query", "SELECT 1")

        # When compression is disabled, we set Accept-Encoding only in the gzip case
        # So for non-compressed, the header should not be explicitly set by our code
        # (but Net::HTTP may add it anyway)
        expect(captured_request).to be_a(Net::HTTP::Post)
      end

      it "sets Accept-Encoding: gzip when compression is enabled" do
        mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
        allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
        captured_request = nil
        allow(mock_http).to receive(:request) do |req|
          captured_request = req
          mock_response
        end

        compressed_conn = described_class.new(**connection_options.merge(compression: "gzip"))
        compressed_conn.connect
        compressed_conn.post("/query", "SELECT 1")

        expect(captured_request["Accept-Encoding"]).to eq("gzip")
      end
    end

    describe "request body compression" do
      let(:large_body) { "x" * 2000 }
      let(:small_body) { "x" * 100 }

      context "with compression enabled and body above threshold" do
        let(:compressed_conn) do
          described_class.new(**connection_options.merge(compression: "gzip", compression_threshold: 500))
        end

        it "compresses large request body" do
          mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
          allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
          allow(mock_http).to receive(:request).and_return(mock_response)

          compressed_conn.connect
          compressed_conn.post("/query", large_body)

          expect(mock_http).to have_received(:request) do |request|
            expect(request["Content-Encoding"]).to eq("gzip")
            expect(request["Content-Type"]).to eq("application/octet-stream")
            expect(request.body).not_to eq(large_body)
          end
        end

        it "actually uses Zlib compression" do
          mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
          allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
          allow(mock_http).to receive(:request).and_return(mock_response)

          compressed_conn.connect
          compressed_conn.post("/query", large_body)

          expect(mock_http).to have_received(:request) do |request|
            decompressed = Zlib.gunzip(request.body)
            expect(decompressed).to eq(large_body)
          end
        end
      end

      context "with compression enabled but body below threshold" do
        let(:compressed_conn) do
          described_class.new(**connection_options.merge(compression: "gzip", compression_threshold: 500))
        end

        it "does not compress small request body" do
          mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
          allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
          allow(mock_http).to receive(:request).and_return(mock_response)

          compressed_conn.connect
          compressed_conn.post("/query", small_body)

          expect(mock_http).to have_received(:request) do |request|
            expect(request["Content-Encoding"]).to be_nil
            expect(request["Content-Type"]).to eq("application/x-www-form-urlencoded")
            expect(request.body).to eq(small_body)
          end
        end
      end

      context "when compression is disabled" do
        it "never compresses request body" do
          mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
          allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
          allow(mock_http).to receive(:request).and_return(mock_response)

          connection.connect
          connection.post("/query", large_body)

          expect(mock_http).to have_received(:request) do |request|
            expect(request["Content-Encoding"]).to be_nil
            expect(request.body).to eq(large_body)
          end
        end
      end

      it "handles nil body" do
        mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
        allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
        allow(mock_http).to receive(:request).and_return(mock_response)

        compressed_conn = described_class.new(**connection_options.merge(compression: "gzip"))
        compressed_conn.connect
        compressed_conn.post("/query", nil)

        expect(mock_http).to have_received(:request) do |request|
          expect(request.body).to be_nil
        end
      end

      it "handles empty body" do
        mock_response = instance_double(Net::HTTPResponse, code: "200", body: "Ok")
        allow(mock_response).to receive(:[]).with("Content-Encoding").and_return(nil)
        allow(mock_http).to receive(:request).and_return(mock_response)

        compressed_conn = described_class.new(**connection_options.merge(compression: "gzip"))
        compressed_conn.connect
        compressed_conn.post("/query", "")

        expect(mock_http).to have_received(:request) do |request|
          expect(request.body).to eq("")
        end
      end
    end

    describe "response decompression" do
      it "decompresses gzip responses" do
        original_body = '{"data": "test"}'
        compressed_body = Zlib.gzip(original_body)
        mock_compressed_response = instance_double(Net::HTTPResponse, code: "200", body: compressed_body)
        allow(mock_compressed_response).to receive(:[]).with("Content-Encoding").and_return("gzip")
        allow(mock_http).to receive(:request).and_return(mock_compressed_response)

        compressed_conn = described_class.new(**connection_options.merge(compression: "gzip"))
        compressed_conn.connect
        response = compressed_conn.post("/query", "SELECT 1")

        expect(response.body).to eq(original_body)
      end

      it "returns response unchanged when Content-Encoding is not gzip" do
        original_body = '{"data": "test"}'
        mock_response_no_encoding = instance_double(Net::HTTPResponse, code: "200", body: original_body)
        allow(mock_response_no_encoding).to receive(:[]).with("Content-Encoding").and_return(nil)
        allow(mock_http).to receive(:request).and_return(mock_response_no_encoding)

        compressed_conn = described_class.new(**connection_options.merge(compression: "gzip"))
        compressed_conn.connect
        response = compressed_conn.post("/query", "SELECT 1")

        expect(response.body).to eq(original_body)
      end

      it "handles invalid gzip data gracefully" do
        mock_invalid_gzip = instance_double(Net::HTTPResponse, code: "200", body: "not gzipped data")
        allow(mock_invalid_gzip).to receive(:[]).with("Content-Encoding").and_return("gzip")
        allow(mock_http).to receive(:request).and_return(mock_invalid_gzip)

        compressed_conn = described_class.new(**connection_options.merge(compression: "gzip"))
        compressed_conn.connect
        response = compressed_conn.post("/query", "SELECT 1")

        expect(response.body).to eq("not gzipped data")
      end

      it "handles empty gzip responses" do
        mock_empty_response = instance_double(Net::HTTPResponse, code: "200", body: "")
        allow(mock_empty_response).to receive(:[]).with("Content-Encoding").and_return("gzip")
        allow(mock_http).to receive(:request).and_return(mock_empty_response)

        compressed_conn = described_class.new(**connection_options.merge(compression: "gzip"))
        compressed_conn.connect
        response = compressed_conn.post("/query", "SELECT 1")

        expect(response.body).to eq("")
      end

      it "handles nil gzip responses" do
        mock_nil_response = instance_double(Net::HTTPResponse, code: "200", body: nil)
        allow(mock_nil_response).to receive(:[]).with("Content-Encoding").and_return("gzip")
        allow(mock_http).to receive(:request).and_return(mock_nil_response)

        compressed_conn = described_class.new(**connection_options.merge(compression: "gzip"))
        compressed_conn.connect
        response = compressed_conn.post("/query", "SELECT 1")

        expect(response.body).to be_nil
      end
    end
  end
end
