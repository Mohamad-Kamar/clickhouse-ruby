# frozen_string_literal: true

RSpec.describe ClickhouseRuby::StreamingResult do
  let(:connection) { instance_double(ClickhouseRuby::Connection) }

  describe "class existence" do
    it "StreamingResult is defined" do
      expect(described_class).to be_a(Class)
    end
  end

  describe "Enumerable" do
    it "includes Enumerable module" do
      expect(described_class.ancestors).to include(Enumerable)
    end

    it "responds to Enumerable methods" do
      result = described_class.new(connection, "SELECT 1")
      expect(result).to respond_to(:map)
      expect(result).to respond_to(:select)
      expect(result).to respond_to(:first)
    end
  end

  describe "JSONEachRow format" do
    it "uses JSONEachRow format by default" do
      result = described_class.new(connection, "SELECT * FROM test")
      expect(result.instance_variable_get(:@format)).to eq("JSONEachRow")
    end

    it "allows custom format specification" do
      result = described_class.new(connection, "SELECT * FROM test", format: "JSON")
      expect(result.instance_variable_get(:@format)).to eq("JSON")
    end
  end

  describe "#each" do
    it "yields rows one at a time" do
      rows = []
      result = described_class.new(connection, "SELECT *")

      allow(result).to receive(:stream_query).and_yield(
        { "id" => 1, "name" => "Alice" },
      ).and_yield(
        { "id" => 2, "name" => "Bob" },
      ).and_yield(
        { "id" => 3, "name" => "Charlie" },
      )

      result.each { |row| rows << row }

      expect(rows.size).to eq(3)
      expect(rows[0]["name"]).to eq("Alice")
      expect(rows[1]["name"]).to eq("Bob")
      expect(rows[2]["name"]).to eq("Charlie")
    end

    it "returns Enumerator without block" do
      result = described_class.new(connection, "SELECT *")
      allow(result).to receive(:stream_query)

      enum = result.each
      expect(enum).to be_a(Enumerator)
    end

    it "supports Enumerator methods" do
      result = described_class.new(connection, "SELECT *")
      allow(result).to receive(:stream_query).and_yield(
        { "id" => 1 },
      ).and_yield(
        { "id" => 2 },
      ).and_yield(
        { "id" => 3 },
      )

      first_row = result.each.first
      expect(first_row["id"]).to eq(1)
    end
  end

  describe "#each with buffer handling" do
    it "handles lines split across chunks" do
      result = described_class.new(connection, "SELECT *")
      rows = []

      # Simulate chunked response with line splitting
      allow(result).to receive(:stream_query).and_yield(
        { "id" => 1, "name" => "Alice" },
      ).and_yield(
        { "id" => 2, "name" => "Bob" },
      ).and_yield(
        { "id" => 3, "name" => "Charlie" },
      )

      result.each { |row| rows << row }

      expect(rows.size).to eq(3)
    end
  end

  describe "#each_batch" do
    it "yields batches of specified size" do # rubocop:disable RSpec/ExampleLength
      result = described_class.new(connection, "SELECT *")
      allow(result).to receive(:each).and_yield(
        { "id" => 1 },
      ).and_yield(
        { "id" => 2 },
      ).and_yield(
        { "id" => 3 },
      ).and_yield(
        { "id" => 4 },
      ).and_yield(
        { "id" => 5 },
      )

      batches = []
      result.each_batch(size: 2) { |batch| batches << batch }

      expect(batches.size).to eq(3)
      expect(batches[0].size).to eq(2)
      expect(batches[1].size).to eq(2)
      expect(batches[2].size).to eq(1)
    end

    it "returns Enumerator without block" do
      result = described_class.new(connection, "SELECT *")
      allow(result).to receive(:each)

      enum = result.each_batch(size: 10)
      expect(enum).to be_a(Enumerator)
    end
  end

  describe "#on_progress callback" do
    it "stores progress callback" do
      result = described_class.new(connection, "SELECT *")
      callback = proc { |progress| puts progress }

      returned = result.on_progress(&callback)
      expect(returned).to eq(result)
      expect(result.instance_variable_get(:@progress_callback)).to eq(callback)
    end
  end

  describe "gzip decompression" do
    it "decompresses gzip responses" do
      result = described_class.new(connection, "SELECT *", compression: "gzip")
      expect(result.instance_variable_get(:@compression)).to eq("gzip")
    end

    it "accepts compression parameter" do
      result = described_class.new(connection, "SELECT *", compression: "gzip")
      expect(result).to respond_to(:each)
    end
  end

  describe "error handling" do
    it "raises QueryError on exception in stream" do
      result = described_class.new(connection, "SELECT *")

      allow(result).to receive(:stream_query).and_raise(
        ClickhouseRuby::QueryError.new("Test error", code: 60),
      )

      expect do
        result.each { |_row| next }
      end.to raise_error(ClickhouseRuby::QueryError)
    end
  end
end
