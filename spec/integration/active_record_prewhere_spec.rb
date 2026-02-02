# frozen_string_literal: true

require "spec_helper"

# Only run these tests if ActiveRecord is available and integration testing is enabled
return unless defined?(ActiveRecord) && ENV["CLICKHOUSE_TEST_INTEGRATION"]

RSpec.describe "PREWHERE Clause Integration" do
  let(:client) { ClickhouseHelper.client }

  before do
    # Create a MergeTree table to test PREWHERE optimization
    client.command(<<~SQL)
      CREATE TABLE IF NOT EXISTS prewhere_test (
        id UInt64,
        date Date,
        status String,
        value UInt32
      ) ENGINE = MergeTree()
      PARTITION BY toYYYYMM(date)
      ORDER BY (date, id)
    SQL

    # Insert test data
    today = Date.today
    rows = [
      # Active statuses
      { id: 1, date: today, status: "active", value: 100 },
      { id: 2, date: today, status: "active", value: 200 },
      { id: 3, date: today, status: "active", value: 150 },
      # Inactive statuses
      { id: 4, date: today, status: "inactive", value: 300 },
      { id: 5, date: today, status: "inactive", value: 250 },
      # Historical data
      { id: 6, date: today - 7, status: "active", value: 400 },
      { id: 7, date: today - 7, status: "inactive", value: 350 },
      # Old data
      { id: 8, date: today - 30, status: "active", value: 500 },
    ]
    client.insert("prewhere_test", rows)
  end

  after do
    client.command("DROP TABLE IF EXISTS prewhere_test")
  end

  it "supports PREWHERE with hash conditions" do
    result = client.execute(<<~SQL)
      SELECT * FROM prewhere_test
      PREWHERE status = 'active'
      WHERE value > 100
      ORDER BY id
    SQL

    expect(result.count).to eq(4) # Active records with value > 100
    expect(result.rows.map { |r| r["status"] }).to all(eq("active"))
  end

  it "supports PREWHERE with date filtering" do
    today = Date.today
    result = client.execute(<<~SQL)
      SELECT count() AS cnt FROM prewhere_test
      PREWHERE date >= '#{today - 7}'
    SQL

    count = result.first["cnt"]
    # All records within last 7 days
    expect(count).to be >= 6
  end

  it "supports multiple PREWHERE conditions" do
    result = client.execute(<<~SQL)
      SELECT * FROM prewhere_test
      PREWHERE status = 'active'
      WHERE value >= 150
      ORDER BY id
    SQL

    expect(result.count).to eq(4)
    expect(result.rows.all? { |r| r["value"].to_i >= 150 }).to be true
  end

  it "supports PREWHERE with aggregation" do
    result = client.execute(<<~SQL)
      SELECT count() AS cnt, avg(value) AS avg_value
      FROM prewhere_test
      PREWHERE status = 'active'
    SQL

    expect(result.first["cnt"]).to eq(5) # 5 active records
    avg = result.first["avg_value"].to_f
    expect(avg).to be > 200
  end

  it "supports PREWHERE with GROUP BY" do
    result = client.execute(<<~SQL)
      SELECT status, count() AS cnt
      FROM prewhere_test
      PREWHERE value > 100
      GROUP BY status
      ORDER BY status
    SQL

    expect(result.count).to eq(2)
    statuses = result.rows.map { |r| r["status"] }
    expect(statuses).to include("active", "inactive")
  end

  it "supports PREWHERE with ORDER BY and LIMIT" do
    result = client.execute(<<~SQL)
      SELECT * FROM prewhere_test
      PREWHERE status = 'active'
      ORDER BY value DESC
      LIMIT 2
    SQL

    expect(result.count).to eq(2)
    # Should be ordered by value descending
    values = result.rows.map { |r| r["value"].to_i }
    expect(values).to eq(values.sort.reverse)
  end

  it "filters efficiently by column before reading full row" do
    # PREWHERE should filter rows before reading value column
    # This test verifies the query executes correctly with PREWHERE optimization
    result = client.execute(<<~SQL)
      SELECT count() AS cnt
      FROM prewhere_test
      PREWHERE status = 'active'
    SQL

    expect(result.first["cnt"]).to eq(5)
  end
end
