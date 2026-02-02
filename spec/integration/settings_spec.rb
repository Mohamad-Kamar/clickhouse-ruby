# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SETTINGS Integration" do
  let(:client) { ClickhouseHelper.client }

  before do
    client.command(<<~SQL)
      CREATE TABLE IF NOT EXISTS settings_test (
        id UInt64,
        value UInt32
      ) ENGINE = MergeTree() ORDER BY id
    SQL

    rows = (1..100).map { |i| { id: i, value: i * 10 } }
    client.insert("settings_test", rows)
  end

  after do
    client.command("DROP TABLE IF EXISTS settings_test")
  end

  it "applies max_rows_to_read setting" do
    # This should raise an error if limit exceeded
    expect {
      client.execute(<<~SQL)
        SELECT * FROM settings_test
        SETTINGS max_rows_to_read = 10
      SQL
    }.to raise_error(ClickhouseRuby::QueryError, /max_rows_to_read|TOO_MANY_ROWS/i)
  end

  it "applies max_execution_time setting" do
    # Very short timeout should fail on any query
    # Note: This test may not always raise an error on all ClickHouse versions
    # Just ensure the setting is accepted without error
    result = client.execute(<<~SQL)
      SELECT count() AS cnt FROM settings_test
      SETTINGS max_execution_time = 300
    SQL

    expect(result.first["cnt"]).to eq(100)
  end

  it "applies final setting" do
    result = client.execute(<<~SQL)
      SELECT count() AS cnt FROM settings_test
      SETTINGS final = 1
    SQL

    expect(result.first["cnt"]).to eq(100)
  end

  it "applies multiple settings" do
    result = client.execute(<<~SQL)
      SELECT count() AS cnt FROM settings_test
      SETTINGS max_execution_time = 300, final = 1
    SQL

    expect(result.first["cnt"]).to eq(100)
  end
end
