# frozen_string_literal: true

require "spec_helper"

# Only run these tests if ActiveRecord is available and integration testing is enabled
return unless defined?(ActiveRecord) && ENV["CLICKHOUSE_TEST_INTEGRATION"]

RSpec.describe "FINAL Modifier Integration" do
  let(:client) { ClickhouseHelper.client }

  before do
    # Create a ReplacingMergeTree table to test FINAL
    client.command(<<~SQL)
      CREATE TABLE IF NOT EXISTS final_test (
        id UInt64,
        name String,
        version UInt32
      ) ENGINE = ReplacingMergeTree(version)
      ORDER BY id
    SQL

    # Insert multiple versions of the same rows
    client.insert("final_test", [
      { id: 1, name: "Alice", version: 1 },
      { id: 1, name: "Alicia", version: 2 }, # Updated version of id=1
      { id: 2, name: "Bob", version: 1 },
      { id: 3, name: "Charlie", version: 1 },
      { id: 3, name: "Charles", version: 2 },
    ],)
  end

  after do
    client.command("DROP TABLE IF EXISTS final_test")
  end

  it "returns all rows without FINAL (may include duplicates)" do
    result = client.execute("SELECT * FROM final_test ORDER BY id, version")

    # May return 5 rows (duplicates not merged yet)
    expect(result.count).to be >= 3
  end

  it "returns deduplicated rows with FINAL" do
    result = client.execute("SELECT * FROM final_test FINAL ORDER BY id")

    # Should return 3 unique IDs (deduplicated)
    expect(result.count).to eq(3)
  end

  it "returns latest versions with FINAL" do
    result = client.execute("SELECT * FROM final_test FINAL ORDER BY id")

    # Check latest versions are returned for each id
    alice = result.find { |r| r["id"] == 1 }
    expect(alice["name"]).to eq("Alicia")
    expect(alice["version"]).to eq(2)
  end

  it "includes all unique ids with latest versions" do
    result = client.execute("SELECT * FROM final_test FINAL ORDER BY id")

    bob = result.find { |r| r["id"] == 2 }
    expect(bob["name"]).to eq("Bob")
    expect(bob["version"]).to eq(1)

    charles = result.find { |r| r["id"] == 3 }
    expect(charles["name"]).to eq("Charles")
    expect(charles["version"]).to eq(2)
  end

  it "supports WHERE clause with FINAL" do
    result = client.execute("SELECT * FROM final_test FINAL WHERE id >= 2 ORDER BY id")

    expect(result.count).to eq(2)
    expect(result.rows.map { |r| r["id"] }).to eq([2, 3])
  end

  it "supports aggregation with FINAL" do
    result = client.execute("SELECT count() AS cnt FROM final_test FINAL")

    expect(result.first["cnt"]).to eq(3)
  end

  it "supports GROUP BY with FINAL" do
    result = client.execute("SELECT name, count() AS cnt FROM final_test FINAL GROUP BY name ORDER BY name")

    expect(result.count).to eq(3)
    expect(result.rows.map { |r| r["cnt"] }).to all(eq(1))
  end
end
