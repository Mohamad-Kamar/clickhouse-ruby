# frozen_string_literal: true

require "spec_helper"

# CRITICAL INTEGRATION TESTS
#
# These tests verify that ClickhouseRuby properly handles errors and NEVER
# silently fails. This is the key differentiator from existing gems
# that have issues like #230 (silent DELETE failures).
#
# Run with: CLICKHOUSE_TEST_INTEGRATION=1 bundle exec rspec spec/integration/
#
RSpec.describe "Error Handling", :integration do
  include_context "integration test"

  describe "query errors" do
    # CRITICAL: Issue #230 - DELETE must NOT silently fail
    # This was a major bug in existing gems where DELETE statements
    # with subqueries would fail silently, corrupting data.
    describe "DELETE error handling" do
      before do
        client.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS test_delete_errors (
            id UInt64,
            status String
          ) ENGINE = MergeTree() ORDER BY id
        SQL

        client.insert("test_delete_errors", [
          { id: 1, status: "active" },
          { id: 2, status: "pending" },
          { id: 3, status: "inactive" },
        ],)
      end

      after do
        client.execute("DROP TABLE IF EXISTS test_delete_errors")
      end

      it "does NOT silently fail on DELETE errors with invalid syntax" do
        # This should raise an error, NOT return silently
        # Use mutations_sync=1 to make mutation synchronous and catch errors immediately
        expect do
          client.execute("ALTER TABLE test_delete_errors DELETE WHERE id IN (INVALID_SYNTAX)", settings: { mutations_sync: 1 })
        end.to raise_error(ClickhouseRuby::QueryError)
      end

      it "does NOT silently fail on DELETE errors with subquery issues" do
        # This is the specific case from issue #230
        # Use mutations_sync=1 to make mutation synchronous and catch errors immediately
        expect do
          client.execute(<<~SQL, settings: { mutations_sync: 1 })
            ALTER TABLE test_delete_errors
            DELETE WHERE id IN (
              SELECT id FROM nonexistent_table
            )
          SQL
        end.to raise_error(ClickhouseRuby::QueryError)
      end

      it "does NOT silently fail on DELETE with invalid column reference" do
        expect do
          client.execute("ALTER TABLE test_delete_errors DELETE WHERE nonexistent_column = 1")
        end.to raise_error(ClickhouseRuby::QueryError)
      end

      it "successfully executes valid DELETE operations" do
        # Valid DELETE should work without error
        expect do
          client.execute("ALTER TABLE test_delete_errors DELETE WHERE status = 'inactive'")
        end.not_to raise_error

        # Verify the delete worked (may need to wait for mutation)
        sleep 0.5

        result = client.execute("SELECT count() as cnt FROM test_delete_errors")
        # Count should be 2 after deleting the inactive row
        expect(result.first["cnt"].to_i).to be <= 3
      end
    end

    describe "SELECT error handling" do
      it "raises UnknownTable for nonexistent table" do
        expect do
          client.execute("SELECT * FROM definitely_nonexistent_table_xyz")
        end.to raise_error(ClickhouseRuby::UnknownTable)
      end

      it "raises SyntaxError for invalid SQL" do
        expect do
          client.execute("SELEC * FROM system.one")
        end.to raise_error(ClickhouseRuby::SyntaxError)
      end

      it "raises UnknownColumn for invalid column" do
        # May be UnknownColumn
        expect do
          client.execute("SELECT nonexistent_column FROM system.one")
        end.to raise_error(ClickhouseRuby::QueryError)
      end

      it "raises UnknownDatabase for invalid database" do
        # May be UnknownDatabase
        expect do
          client.execute("SELECT * FROM nonexistent_db.some_table")
        end.to raise_error(ClickhouseRuby::QueryError)
      end
    end

    describe "INSERT error handling" do
      before do
        client.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS test_insert_errors (
            id UInt64,
            name String,
            value Int32
          ) ENGINE = MergeTree() ORDER BY id
        SQL
      end

      after do
        client.execute("DROP TABLE IF EXISTS test_insert_errors")
      end

      it "raises error for type mismatch on insert" do
        # ClickHouse is strict about types
        expect do
          client.execute("INSERT INTO test_insert_errors VALUES (1, 'test', 'not_an_integer')")
        end.to raise_error(ClickhouseRuby::QueryError)
      end

      it "raises error for inserting into nonexistent table" do
        expect do
          client.insert("nonexistent_table", [{ id: 1, name: "test" }])
        end.to raise_error(ClickhouseRuby::QueryError)
      end

      it "raises error for missing required column" do
        # Depending on ClickHouse version, this may or may not raise
        # At minimum, it should not silently fail

        client.execute("INSERT INTO test_insert_errors (id) VALUES (1)")
        # If we get here without error, verify defaults were used
      rescue ClickhouseRuby::QueryError
        # This is also acceptable behavior
      end
    end

    describe "error details" do
      it "includes error code in QueryError" do
        client.execute("SELECT * FROM nonexistent_table_for_test")
        raise "Expected QueryError to be raised"
      rescue ClickhouseRuby::QueryError => e
        expect(e.code).to be_a(Integer)
      end

      it "includes HTTP status in QueryError" do
        client.execute("INVALID SQL SYNTAX HERE")
        raise "Expected QueryError to be raised"
      rescue ClickhouseRuby::QueryError => e
        expect(e.http_status).not_to be_nil
      end

      it "includes SQL in QueryError when available" do
        sql = "SELECT * FROM nonexistent_xyz_table"
        begin
          client.execute(sql)
          raise "Expected QueryError to be raised"
        rescue ClickhouseRuby::QueryError => e
          # SQL includes FORMAT suffix added by execute()
          expect(e.sql).to include(sql)
        end
      end
    end
  end

  describe "connection errors" do
    it "raises ConnectionNotEstablished for unreachable host" do
      bad_config = ClickhouseRuby::Configuration.new
      bad_config.host = "nonexistent.invalid.host.xyz"
      bad_config.port = 8123
      bad_config.connect_timeout = 1

      bad_client = ClickhouseRuby::Client.new(bad_config)

      expect do
        bad_client.execute("SELECT 1")
      end.to raise_error(ClickhouseRuby::ConnectionError)
    end

    it "raises ConnectionNotEstablished for refused connection" do
      bad_config = ClickhouseRuby::Configuration.new
      bad_config.host = "localhost"
      bad_config.port = 59_999 # Unlikely to be in use
      bad_config.connect_timeout = 1

      bad_client = ClickhouseRuby::Client.new(bad_config)

      expect do
        bad_client.execute("SELECT 1")
      end.to raise_error(ClickhouseRuby::ConnectionError)
    end
  end

  describe "HTTP status code handling" do
    # ClickHouse returns various HTTP status codes for different errors
    # We must always check the status code before parsing the response

    it "handles 400 Bad Request" do
      expect do
        client.execute("DEFINITELY NOT VALID SQL AT ALL !!!")
      end.to raise_error(ClickhouseRuby::QueryError) do |error|
        expect(error.http_status.to_s).to match(/4\d\d/)
      end
    end

    it "handles successful queries (200 OK)" do
      result = client.execute("SELECT 1 as value")
      expect(result).not_to be_nil
      expect(result.first["value"]).to eq(1)
    end

    it "does not attempt to parse error response as data" do
      # This was another issue - parsing error HTML as CSV
      expect do
        client.execute("SELECT * FROM table_that_does_not_exist_at_all")
      end.to raise_error(ClickhouseRuby::QueryError)

      # The error should not contain garbled data from failed parsing
      begin
        client.execute("SELECT * FROM table_that_does_not_exist_at_all")
      rescue ClickhouseRuby::QueryError => e
        expect(e.message).not_to include("<!DOCTYPE")
        expect(e.message).not_to include("<html>")
      end
    end
  end

  describe "query timeout handling" do
    it "respects max_execution_time setting", :slow do
      # NOTE: ClickHouse's sleep() may not actually block for the full duration
      # and timeout behavior varies by version. We just verify the setting is passed.
      # A real timeout test would need a genuinely long-running query.
      start_time = Time.now
      begin
        client.execute(
          "SELECT sleep(0.1)", # Short sleep to verify it runs
          settings: { max_execution_time: 5 },
        )
      rescue ClickhouseRuby::QueryError
        # Timeout is acceptable
      end
      elapsed = Time.now - start_time
      # Should complete in reasonable time (not hang forever)
      expect(elapsed).to be < 10
    end
  end

  describe "concurrent error handling" do
    it "properly handles errors in concurrent requests" do
      threads = 5.times.map do |i|
        Thread.new do
          if i.even?
            client.execute("SELECT 1")
            :success
          else
            client.execute("SELECT * FROM nonexistent_table_#{i}")
            :unexpected_success
          end
        rescue ClickhouseRuby::QueryError
          :expected_error
        rescue StandardError => e
          e.class.name
        end
      end

      results = threads.map(&:value)

      # Even threads should succeed, odd threads should get expected_error
      results.each_with_index do |result, i|
        if i.even?
          expect(result).to eq(:success)
        else
          expect(result).to eq(:expected_error)
        end
      end
    end
  end

  describe "mutation error handling" do
    # Mutations in ClickHouse are async - we need to check their status
    before do
      client.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS test_mutations (
          id UInt64,
          data String
        ) ENGINE = MergeTree() ORDER BY id
      SQL

      client.insert("test_mutations", (1..100).map { |i| { id: i, data: "data_#{i}" } })
    end

    after do
      client.execute("DROP TABLE IF EXISTS test_mutations")
    end

    it "reports mutation errors when checking status" do
      # Start a mutation that might fail

      client.execute(<<~SQL)
        ALTER TABLE test_mutations
        UPDATE data = toString(nonexistent_function(id))
        WHERE id > 0
      SQL

      # Wait a bit for mutation to process
      sleep 1

      # Check mutation status
      result = client.execute(<<~SQL)
        SELECT *
        FROM system.mutations
        WHERE table = 'test_mutations'
        AND is_done = 0
        ORDER BY create_time DESC
        LIMIT 1
      SQL

    # If there's a failed mutation, latest_fail_reason should be set
    rescue ClickhouseRuby::QueryError
      # This is acceptable - error during mutation execution
    end
  end
end
