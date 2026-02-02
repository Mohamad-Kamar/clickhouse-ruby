# frozen_string_literal: true

require "spec_helper"

# Only run these tests if ActiveRecord is available and integration testing is enabled
return unless defined?(ActiveRecord) && ENV["CLICKHOUSE_TEST_INTEGRATION"]

RSpec.describe "SAMPLE Clause Integration" do
  let(:client) { ClickhouseHelper.client }

  before do
    # Create a table with SAMPLE BY clause for sampling support
    client.command(<<~SQL)
      CREATE TABLE IF NOT EXISTS sample_test (
        id UInt64,
        value UInt32,
        category String
      ) ENGINE = MergeTree()
      SAMPLE BY intHash32(id)
      ORDER BY id
    SQL

    # Insert a reasonable number of rows for sampling
    rows = (1..1000).map { |i| { id: i, value: i * 10, category: (i % 5).zero? ? "A" : "B" } }
    client.insert("sample_test", rows)
  end

  after do
    client.command("DROP TABLE IF EXISTS sample_test")
  end

  it "supports fractional sampling" do
    # SAMPLE 0.1 should return approximately 10% of 1000 = 100 rows (±20% tolerance)
    result = client.execute("SELECT count() AS cnt FROM sample_test SAMPLE 0.1")

    count = result.first["cnt"]
    expect(count).to be > 50   # At least 50 rows
    expect(count).to be < 200  # At most 200 rows (more lenient for sampling variability)
  end

  it "supports absolute row count sampling" do
    # SAMPLE 100 should return at least 100 rows
    result = client.execute("SELECT count() AS cnt FROM sample_test SAMPLE 100")

    count = result.first["cnt"]
    expect(count).to be >= 100
  end

  it "supports SAMPLE with OFFSET for deterministic results" do
    # First sample with offset
    result1 = client.execute("SELECT * FROM sample_test SAMPLE 0.1 OFFSET 0.0 ORDER BY id LIMIT 5")
    ids1 = result1.rows.map { |r| r["id"] }

    # Second sample with same offset should give same results
    result2 = client.execute("SELECT * FROM sample_test SAMPLE 0.1 OFFSET 0.0 ORDER BY id LIMIT 5")
    ids2 = result2.rows.map { |r| r["id"] }

    expect(ids1).to eq(ids2)
  end

  it "supports SAMPLE with WHERE clause" do
    # Sample and filter for category A
    result = client.execute(<<~SQL)
      SELECT count() AS cnt FROM sample_test
      SAMPLE 0.2
      WHERE category = 'A'
    SQL

    count = result.first["cnt"]
    # Should be roughly 20% of ~200 (20% of 1000) = ~40 rows (±50% tolerance for sampling)
    expect(count).to be > 10
  end

  it "supports SAMPLE with aggregation" do
    result = client.execute("SELECT avg(value) AS avg_value FROM sample_test SAMPLE 0.5")

    avg = result.first["avg_value"].to_f
    # Average should be roughly 5000 (500 * 10 from 1..1000 with value = i * 10)
    expect(avg).to be > 4000
    expect(avg).to be < 6000
  end

  it "supports SAMPLE with GROUP BY" do
    result = client.execute(<<~SQL)
      SELECT category, count() AS cnt
      FROM sample_test
      SAMPLE 0.2
      GROUP BY category
      ORDER BY category
    SQL

    expect(result.count).to be >= 1  # Should have at least one category in sample
  end
end
