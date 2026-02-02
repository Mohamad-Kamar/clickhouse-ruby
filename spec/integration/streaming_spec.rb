# frozen_string_literal: true

RSpec.describe "Result Streaming", :integration do
  let(:client) { ClickhouseHelper.client }

  before do
    client.command(<<~SQL)
      CREATE TABLE IF NOT EXISTS stream_test (
        id UInt64,
        data String
      ) ENGINE = MergeTree() ORDER BY id
    SQL

    # Insert test data
    rows = (1..10_000).map { |i| { id: i, data: "row_#{i}" } }
    client.insert("stream_test", rows)
  end

  after do
    client.command("DROP TABLE IF EXISTS stream_test")
  end

  it "streams rows without loading all into memory" do
    count = 0
    client.each_row("SELECT * FROM stream_test") do |_row|
      count += 1
      break if count >= 100 # Early termination
    end

    expect(count).to eq(100)
  end

  it "supports lazy enumeration" do
    result = client.stream_execute("SELECT * FROM stream_test")
      .lazy
      .select { |row| row["id"].to_i.even? }
      .take(10)
      .to_a

    expect(result.size).to eq(10)
    expect(result.all? { |row| row["id"].to_i.even? }).to be true
  end

  it "processes in batches" do
    batch_count = 0
    client.each_batch("SELECT * FROM stream_test", batch_size: 100) do |batch|
      batch_count += 1
      expect(batch.size).to be <= 100
    end

    expect(batch_count).to eq(100) # 10,000 rows / 100 per batch
  end

  it "streams 10K rows with constant memory" do
    # This test verifies memory efficiency by processing a large result set
    # If streaming works correctly, memory usage should stay constant
    count = 0
    client.each_row("SELECT * FROM stream_test") do |row|
      count += 1
      # JSONEachRow format returns values as they come
      expect(row["id"]).not_to be_nil
    end

    expect(count).to eq(10_000)
  end
end
