# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::RetryHandler do
  subject(:handler) do
    described_class.new(
      max_attempts: 3,
      initial_backoff: 0.1,
      max_backoff: 1.0,
      multiplier: 2.0,
      jitter: :none,
    )
  end

  describe "#initialize" do
    it "sets max_attempts" do
      expect(handler.max_attempts).to eq(3)
    end

    it "sets initial_backoff" do
      expect(handler.initial_backoff).to eq(0.1)
    end

    it "sets max_backoff" do
      expect(handler.max_backoff).to eq(1.0)
    end

    it "sets multiplier" do
      expect(handler.multiplier).to eq(2.0)
    end

    it "sets jitter strategy" do
      expect(handler.jitter).to eq(:none)
    end

    it "uses default values when not provided" do
      handler = described_class.new
      expect(handler.max_attempts).to eq(3)
      expect(handler.initial_backoff).to eq(1.0)
      expect(handler.max_backoff).to eq(120.0)
      expect(handler.multiplier).to eq(1.6)
      expect(handler.jitter).to eq(:equal)
    end
  end

  describe "#with_retry" do
    context "when operation succeeds on first attempt" do
      it "returns result without retry" do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          "success"
        end

        expect(result).to eq("success")
        expect(call_count).to eq(1)
      end
    end

    context "when operation succeeds after transient failure" do
      it "retries and returns result" do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          raise ClickhouseRuby::ConnectionError, "network error" if call_count < 2

          "success"
        end

        expect(result).to eq("success")
        expect(call_count).to eq(2)
      end

      it "retries with ConnectionTimeout" do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          raise ClickhouseRuby::ConnectionTimeout, "timeout" if call_count < 2

          "success"
        end

        expect(result).to eq("success")
        expect(call_count).to eq(2)
      end

      it "retries with ConnectionNotEstablished" do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          raise ClickhouseRuby::ConnectionNotEstablished, "not established" if call_count < 2

          "success"
        end

        expect(result).to eq("success")
        expect(call_count).to eq(2)
      end

      it "retries with PoolTimeout" do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          raise ClickhouseRuby::PoolTimeout, "pool timeout" if call_count < 2

          "success"
        end

        expect(result).to eq("success")
        expect(call_count).to eq(2)
      end
    end

    context "when all retries are exhausted" do
      it "raises retriable ConnectionError" do
        call_count = 0
        expect do
          handler.with_retry do
            call_count += 1
            raise ClickhouseRuby::ConnectionError, "network error"
          end
        end.to raise_error(ClickhouseRuby::ConnectionError, /network error/)

        expect(call_count).to eq(3)
      end
    end

    context "when operation fails with non-retriable error" do
      it "does not retry on SyntaxError" do
        call_count = 0
        expect do
          handler.with_retry do
            call_count += 1
            raise ClickhouseRuby::SyntaxError, "bad SQL"
          end
        end.to raise_error(ClickhouseRuby::SyntaxError, /bad SQL/)

        expect(call_count).to eq(1)
      end

      it "does not retry on StatementInvalid" do
        call_count = 0
        expect do
          handler.with_retry do
            call_count += 1
            raise ClickhouseRuby::StatementInvalid, "unknown table"
          end
        end.to raise_error(ClickhouseRuby::StatementInvalid)

        expect(call_count).to eq(1)
      end
    end

    context "with HTTP error responses" do
      it "retries on HTTP 500" do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          if call_count < 2
            error = ClickhouseRuby::QueryError.new("Server error", http_status: "500")
            raise error
          end
          "success"
        end

        expect(result).to eq("success")
        expect(call_count).to eq(2)
      end

      it "retries on HTTP 502" do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          if call_count < 2
            error = ClickhouseRuby::QueryError.new("Bad gateway", http_status: "502")
            raise error
          end
          "success"
        end

        expect(result).to eq("success")
        expect(call_count).to eq(2)
      end

      it "retries on HTTP 503" do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          if call_count < 2
            error = ClickhouseRuby::QueryError.new("Service unavailable", http_status: "503")
            raise error
          end
          "success"
        end

        expect(result).to eq("success")
        expect(call_count).to eq(2)
      end

      it "retries on HTTP 504" do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          if call_count < 2
            error = ClickhouseRuby::QueryError.new("Gateway timeout", http_status: "504")
            raise error
          end
          "success"
        end

        expect(result).to eq("success")
        expect(call_count).to eq(2)
      end

      it "retries on HTTP 429 (rate limit)" do
        call_count = 0
        result = handler.with_retry do
          call_count += 1
          if call_count < 2
            error = ClickhouseRuby::QueryError.new("Too many requests", http_status: "429")
            raise error
          end
          "success"
        end

        expect(result).to eq("success")
        expect(call_count).to eq(2)
      end

      it "does not retry on HTTP 400" do
        call_count = 0
        expect do
          handler.with_retry do
            call_count += 1
            error = ClickhouseRuby::QueryError.new("Bad request", http_status: "400")
            raise error
          end
        end.to raise_error(ClickhouseRuby::QueryError, /Bad request/)

        expect(call_count).to eq(1)
      end

      it "does not retry on HTTP 404" do
        call_count = 0
        expect do
          handler.with_retry do
            call_count += 1
            error = ClickhouseRuby::QueryError.new("Not found", http_status: "404")
            raise error
          end
        end.to raise_error(ClickhouseRuby::QueryError, /Not found/)

        expect(call_count).to eq(1)
      end
    end

    context "with idempotency flag" do
      it "warns when retrying non-idempotent operation" do
        call_count = 0
        expect do
          expect(handler).to receive(:warn).at_least(:once)
          handler.with_retry(idempotent: false) do
            call_count += 1
            raise ClickhouseRuby::ConnectionError if call_count < 2

            "success"
          end
        end.not_to raise_error
      end

      it "does not warn when retrying idempotent operation" do
        call_count = 0
        expect do
          expect(handler).not_to receive(:warn)
          handler.with_retry(idempotent: true) do
            call_count += 1
            raise ClickhouseRuby::ConnectionError if call_count < 2

            "success"
          end
        end.not_to raise_error
      end
    end

    context "with query_id" do
      it "passes provided query_id to block" do
        provided_id = "custom-query-id"
        received_id = nil
        handler.with_retry(query_id: provided_id) do |qid|
          received_id = qid
        end

        expect(received_id).to eq(provided_id)
      end

      it "generates query_id if not provided" do
        received_id = nil
        handler.with_retry do |qid|
          received_id = qid
        end

        expect(received_id).not_to be_nil
        expect(received_id).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
      end

      it "reuses query_id on retries" do
        query_ids = []
        call_count = 0
        handler.with_retry do |qid|
          call_count += 1
          query_ids << qid
          raise ClickhouseRuby::ConnectionError if call_count < 2
        end

        expect(query_ids.uniq.length).to eq(1)
      end
    end
  end

  describe "#retriable?" do
    it "returns true for ConnectionError" do
      error = ClickhouseRuby::ConnectionError.new("test")
      expect(handler.retriable?(error)).to be true
    end

    it "returns true for ConnectionTimeout" do
      error = ClickhouseRuby::ConnectionTimeout.new("test")
      expect(handler.retriable?(error)).to be true
    end

    it "returns true for PoolTimeout" do
      error = ClickhouseRuby::PoolTimeout.new("test")
      expect(handler.retriable?(error)).to be true
    end

    it "returns true for HTTP 500" do
      error = ClickhouseRuby::QueryError.new("error", http_status: "500")
      expect(handler.retriable?(error)).to be true
    end

    it "returns false for SyntaxError" do
      error = ClickhouseRuby::SyntaxError.new("test")
      expect(handler.retriable?(error)).to be false
    end

    it "returns false for HTTP 400" do
      error = ClickhouseRuby::QueryError.new("error", http_status: "400")
      expect(handler.retriable?(error)).to be false
    end
  end

  describe "#calculate_delay (exponential backoff)" do
    context "with exponential backoff formula" do
      it "calculates correct delays" do
        # jitter: :none to get deterministic values
        handler = described_class.new(
          initial_backoff: 0.1,
          max_backoff: 1.0,
          multiplier: 2.0,
          jitter: :none,
        )

        delay1 = handler.send(:calculate_delay, 1)
        delay2 = handler.send(:calculate_delay, 2)
        delay3 = handler.send(:calculate_delay, 3)

        # delay = 0.1 * 2^(n-1)
        expect(delay1).to eq(0.1)   # 0.1 * 2^0
        expect(delay2).to eq(0.2)   # 0.1 * 2^1
        expect(delay3).to eq(0.4)   # 0.1 * 2^2
      end

      it "caps at max_backoff" do
        handler = described_class.new(
          initial_backoff: 0.1,
          max_backoff: 1.0,
          multiplier: 2.0,
          jitter: :none,
        )

        delay100 = handler.send(:calculate_delay, 100)
        expect(delay100).to eq(1.0)
      end
    end

    context "equal jitter strategy" do
      it "applies equal jitter: delay/2 + random(0, delay/2)" do
        handler = described_class.new(
          initial_backoff: 1.0,
          max_backoff: 10.0,
          multiplier: 1.0,
          jitter: :equal,
        )

        delays = 100.times.map { handler.send(:calculate_delay, 1) }

        # Equal jitter: delay/2 + random(0, delay/2)
        # For delay=1.0, should be between 0.5 and 1.0
        expect(delays.min).to be >= 0.5
        expect(delays.max).to be <= 1.0
        expect(delays.uniq.size).to be > 1 # Some variance
      end
    end

    context "full jitter strategy" do
      it "applies full jitter: random(0, delay)" do
        handler = described_class.new(
          initial_backoff: 1.0,
          max_backoff: 10.0,
          multiplier: 1.0,
          jitter: :full,
        )

        delays = 100.times.map { handler.send(:calculate_delay, 1) }

        # Full jitter: random(0, delay)
        # For delay=1.0, should be between 0 and 1.0
        expect(delays.min).to be >= 0.0
        expect(delays.max).to be <= 1.0
        expect(delays.uniq.size).to be > 1
      end
    end

    context "no jitter strategy" do
      it "returns deterministic delay" do
        handler = described_class.new(
          initial_backoff: 0.1,
          max_backoff: 1.0,
          multiplier: 2.0,
          jitter: :none,
        )

        delays = 5.times.map { handler.send(:calculate_delay, 1) }

        # All should be the same
        expect(delays.uniq.length).to eq(1)
        expect(delays.first).to eq(0.1)
      end
    end
  end

  describe "integration with actual retry flow" do
    it "sleeps between retries" do
      handler = described_class.new(
        max_attempts: 2,
        initial_backoff: 0.01,
        max_backoff: 0.1,
        multiplier: 2.0,
        jitter: :none,
      )

      call_count = 0
      start_time = Time.now
      result = handler.with_retry do
        call_count += 1
        raise ClickhouseRuby::ConnectionError if call_count < 2

        "success"
      end

      elapsed = Time.now - start_time

      expect(result).to eq("success")
      expect(call_count).to eq(2)
      expect(elapsed).to be >= 0.01  # Should have slept
    end
  end
end
