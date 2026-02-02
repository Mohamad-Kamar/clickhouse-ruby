# frozen_string_literal: true

require "spec_helper"

RSpec.describe ClickhouseRuby::Instrumentation do
  describe ".available?" do
    context "when ActiveSupport::Notifications is defined" do
      it "returns truthy when AS is available" do
        # The method returns the result of defined?(), which can be truthy or nil
        result = described_class.available?
        # defined? returns a string like "constant" when defined, nil otherwise
        if defined?(ActiveSupport::Notifications)
          expect(result).to be_truthy
        else
          expect(result).to be_falsy
        end
      end
    end
  end

  describe ".monotonic_time" do
    it "returns a monotonic timestamp" do
      time1 = described_class.monotonic_time
      sleep(0.01)
      time2 = described_class.monotonic_time

      expect(time2).to be > time1
    end

    it "returns a Float" do
      expect(described_class.monotonic_time).to be_a(Float)
    end
  end

  describe ".duration_ms" do
    it "calculates duration in milliseconds" do
      started_at = described_class.monotonic_time
      sleep(0.05)
      duration = described_class.duration_ms(started_at)

      expect(duration).to be >= 50
      expect(duration).to be < 200 # Allow for some variance
    end
  end

  describe ".instrument" do
    context "when ActiveSupport::Notifications is available", if: defined?(ActiveSupport::Notifications) do
      it "instruments through ActiveSupport::Notifications" do
        events = []
        ActiveSupport::Notifications.subscribe("test.event") do |*args|
          events << ActiveSupport::Notifications::Event.new(*args)
        end

        result = described_class.instrument("test.event", key: "value") do
          "block_result"
        end

        expect(result).to eq("block_result")
        expect(events.size).to eq(1)
        expect(events.first.payload[:key]).to eq("value")

        ActiveSupport::Notifications.unsubscribe("test.event")
      end
    end

    context "when ActiveSupport::Notifications is not available" do
      before do
        allow(described_class).to receive(:available?).and_return(false)
      end

      it "executes the block and tracks timing" do
        payload = { test: true }

        result = described_class.instrument("test.event", payload) do
          sleep(0.01)
          "result"
        end

        expect(result).to eq("result")
        expect(payload[:duration_ms]).to be >= 10
      end

      it "tracks timing even on error" do
        payload = { test: true }

        expect do
          described_class.instrument("test.event", payload) do
            raise StandardError, "test error"
          end
        end.to raise_error(StandardError, "test error")

        expect(payload[:duration_ms]).to be_a(Numeric)
        expect(payload[:exception]).to eq(["StandardError", "test error"])
      end
    end
  end

  describe ".publish" do
    context "when ActiveSupport::Notifications is available", if: defined?(ActiveSupport::Notifications) do
      it "publishes an event" do
        events = []
        ActiveSupport::Notifications.subscribe("test.publish") do |*args|
          events << args
        end

        described_class.publish("test.publish", data: "value")

        # publish is synchronous
        expect(events.size).to eq(1)

        ActiveSupport::Notifications.unsubscribe("test.publish")
      end
    end

    context "when ActiveSupport::Notifications is not available" do
      before do
        allow(described_class).to receive(:available?).and_return(false)
      end

      it "does nothing" do
        expect { described_class.publish("test.event", data: "value") }.not_to raise_error
      end
    end
  end

  describe "EVENTS" do
    it "defines all expected events" do
      expect(described_class::EVENTS).to include(
        query_start: "clickhouse_ruby.query.start",
        query_complete: "clickhouse_ruby.query.complete",
        query_error: "clickhouse_ruby.query.error",
        insert_start: "clickhouse_ruby.insert.start",
        insert_complete: "clickhouse_ruby.insert.complete",
        pool_checkout: "clickhouse_ruby.pool.checkout",
        pool_checkin: "clickhouse_ruby.pool.checkin",
        pool_timeout: "clickhouse_ruby.pool.timeout",
      )
    end

    it "is frozen" do
      expect(described_class::EVENTS).to be_frozen
    end
  end
end

RSpec.describe ClickhouseRuby::Instrumentation::Helpers do
  let(:test_class) do
    Class.new do
      include ClickhouseRuby::Instrumentation::Helpers

      def test_instrument_query(sql, settings = {})
        instrument_query(sql, settings: settings) { "query_result" }
      end

      def test_instrument_insert(table, row_count, settings = {})
        instrument_insert(table, row_count: row_count, settings: settings) { "insert_result" }
      end

      def test_instrument_pool_checkout
        instrument_pool_checkout { "checkout_result" }
      end

      def test_publish_pool_timeout(wait_time)
        publish_pool_timeout(wait_time: wait_time)
      end
    end
  end

  let(:instance) { test_class.new }

  describe "#instrument_query" do
    it "executes the block and returns the result" do
      result = instance.test_instrument_query("SELECT 1", { max_rows: 100 })
      expect(result).to eq("query_result")
    end
  end

  describe "#instrument_insert" do
    it "executes the block and returns the result" do
      result = instance.test_instrument_insert("events", 100, { async_insert: true })
      expect(result).to eq("insert_result")
    end
  end

  describe "#instrument_pool_checkout" do
    it "executes the block and returns the result" do
      result = instance.test_instrument_pool_checkout
      expect(result).to eq("checkout_result")
    end
  end

  describe "#publish_pool_timeout" do
    it "does not raise an error" do
      expect { instance.test_publish_pool_timeout(5.0) }.not_to raise_error
    end
  end
end
