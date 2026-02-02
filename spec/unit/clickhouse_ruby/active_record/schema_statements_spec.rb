# frozen_string_literal: true

require "spec_helper"

# Only run these tests if ActiveRecord is available
# Guard must be at file level since constant resolution happens at parse time
return unless defined?(ActiveRecord) && defined?(ClickhouseRuby::ActiveRecord::SchemaStatements)

RSpec.describe ClickhouseRuby::ActiveRecord::SchemaStatements do
  let(:config) do
    {
      host: "localhost",
      port: 8123,
      database: "test_db",
    }
  end

  let(:adapter) { ClickhouseRuby::ActiveRecord::ConnectionAdapter.new(nil, nil, nil, config) }
  let(:mock_client) { instance_double(ClickhouseRuby::Client) }

  before do
    allow(ClickhouseRuby::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:close)
    adapter.connect
  end

  describe "#tables" do
    let(:mock_result) do
      instance_double(ClickhouseRuby::Result).tap do |r|
        allow(r).to receive(:map).and_return(%w[events users orders])
        allow(r).to receive(:error?).and_return(false)
      end
    end

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "queries system.tables" do
      expect(mock_client).to receive(:execute) do |sql|
        expect(sql).to include("system.tables")
        expect(sql).to include("currentDatabase()")
        expect(sql).not_to include("'View'")
        mock_result
      end
      adapter.tables
    end

    it "returns table names" do
      expect(adapter.tables).to eq(%w[events users orders])
    end
  end

  describe "#views" do
    let(:mock_result) do
      instance_double(ClickhouseRuby::Result).tap do |r|
        allow(r).to receive(:map).and_return(%w[events_view summary_view])
        allow(r).to receive(:error?).and_return(false)
      end
    end

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "queries system.tables for views" do
      expect(mock_client).to receive(:execute) do |sql|
        expect(sql).to include("system.tables")
        expect(sql).to include("'View'")
        expect(sql).to include("'MaterializedView'")
        mock_result
      end
      adapter.views
    end

    it "returns view names" do
      expect(adapter.views).to eq(%w[events_view summary_view])
    end
  end

  describe "#table_exists?" do
    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    context "when table exists" do
      let(:mock_result) do
        instance_double(ClickhouseRuby::Result, any?: true, error?: false)
      end

      it "returns true" do
        expect(adapter.table_exists?("events")).to be true
      end
    end

    context "when table does not exist" do
      let(:mock_result) do
        instance_double(ClickhouseRuby::Result, any?: false, error?: false)
      end

      it "returns false" do
        expect(adapter.table_exists?("nonexistent")).to be false
      end
    end
  end

  describe "#columns" do
    let(:mock_result) do
      instance_double(ClickhouseRuby::Result).tap do |r|
        allow(r).to receive(:map).and_return([])
        allow(r).to receive(:error?).and_return(false)
      end
    end

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "queries system.columns" do
      expect(mock_client).to receive(:execute) do |sql|
        expect(sql).to include("system.columns")
        expect(sql).to include("table = 'events'")
        mock_result
      end
      adapter.columns("events")
    end
  end

  describe "#primary_keys" do
    let(:mock_result) do
      instance_double(ClickhouseRuby::Result).tap do |r|
        allow(r).to receive(:map).and_return(["id"])
        allow(r).to receive(:empty?).and_return(false)
        allow(r).to receive(:error?).and_return(false)
      end
    end

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "queries system.columns for primary key columns" do
      expect(mock_client).to receive(:execute) do |sql|
        expect(sql).to include("is_in_primary_key = 1")
        mock_result
      end
      adapter.primary_keys("events")
    end

    it "returns primary key columns" do
      expect(adapter.primary_keys("events")).to eq(["id"])
    end

    context "when no primary key" do
      let(:mock_result) do
        instance_double(ClickhouseRuby::Result).tap do |r|
          allow(r).to receive(:map).and_return([])
          allow(r).to receive(:empty?).and_return(true)
          allow(r).to receive(:error?).and_return(false)
        end
      end

      it "returns nil" do
        expect(adapter.primary_keys("events")).to be_nil
      end
    end
  end

  describe "#indexes" do
    let(:mock_result) do
      instance_double(ClickhouseRuby::Result).tap do |r|
        allow(r).to receive(:map).and_return([{ name: "idx_status", type: "minmax", expression: "status", granularity: 1 }])
        allow(r).to receive(:error?).and_return(false)
      end
    end

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "queries system.data_skipping_indices" do
      expect(mock_client).to receive(:execute) do |sql|
        expect(sql).to include("system.data_skipping_indices")
        mock_result
      end
      adapter.indexes("events")
    end
  end

  describe "#drop_table" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates DROP TABLE statement" do
      expect(mock_client).to receive(:execute).with(/DROP TABLE `events`/, anything)
      adapter.drop_table("events")
    end

    it "includes IF EXISTS when specified" do
      expect(mock_client).to receive(:execute).with(/DROP TABLE IF EXISTS/, anything)
      adapter.drop_table("events", if_exists: true)
    end
  end

  describe "#rename_table" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates RENAME TABLE statement" do
      expect(mock_client).to receive(:execute).with(/RENAME TABLE `old_events` TO `new_events`/, anything)
      adapter.rename_table("old_events", "new_events")
    end
  end

  describe "#truncate_table" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates TRUNCATE TABLE statement" do
      expect(mock_client).to receive(:execute).with(/TRUNCATE TABLE `events`/, anything)
      adapter.truncate_table("events")
    end
  end

  describe "#add_column" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates ALTER TABLE ADD COLUMN" do
      expect(mock_client).to receive(:execute).with(/ALTER TABLE .* ADD COLUMN `status` Nullable\(String\)/, anything)
      adapter.add_column("events", "status", :string)
    end

    it "handles AFTER clause" do
      expect(mock_client).to receive(:execute).with(/AFTER `id`/, anything)
      adapter.add_column("events", "status", :string, after: "id")
    end

    it "handles DEFAULT clause" do
      expect(mock_client).to receive(:execute).with(/DEFAULT/, anything)
      adapter.add_column("events", "status", :string, default: "pending")
    end

    it "handles non-nullable columns" do
      expect(mock_client).to receive(:execute).with(/ADD COLUMN `status` String/, anything)
      adapter.add_column("events", "status", :string, null: false)
    end
  end

  describe "#remove_column" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates ALTER TABLE DROP COLUMN" do
      expect(mock_client).to receive(:execute).with(/ALTER TABLE .* DROP COLUMN `status`/, anything)
      adapter.remove_column("events", "status")
    end
  end

  describe "#rename_column" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates ALTER TABLE RENAME COLUMN" do
      expect(mock_client).to receive(:execute).with(/RENAME COLUMN `old_name` TO `new_name`/, anything)
      adapter.rename_column("events", "old_name", "new_name")
    end
  end

  describe "#change_column" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates ALTER TABLE MODIFY COLUMN" do
      expect(mock_client).to receive(:execute).with(/MODIFY COLUMN `status` Nullable\(Int32\)/, anything)
      adapter.change_column("events", "status", :integer)
    end
  end

  describe "#add_index" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates ALTER TABLE ADD INDEX" do
      expect(mock_client).to receive(:execute).with(/ADD INDEX .* TYPE minmax GRANULARITY 1/, anything)
      adapter.add_index("events", "status")
    end

    it "uses custom index type" do
      expect(mock_client).to receive(:execute).with(/TYPE bloom_filter/, anything)
      adapter.add_index("events", "status", type: "bloom_filter")
    end

    it "uses custom granularity" do
      expect(mock_client).to receive(:execute).with(/GRANULARITY 4/, anything)
      adapter.add_index("events", "status", granularity: 4)
    end

    it "uses custom index name" do
      expect(mock_client).to receive(:execute).with(/ADD INDEX `custom_idx`/, anything)
      adapter.add_index("events", "status", name: "custom_idx")
    end
  end

  describe "#remove_index" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates ALTER TABLE DROP INDEX" do
      expect(mock_client).to receive(:execute).with(/DROP INDEX `idx_status`/, anything)
      adapter.remove_index("events", name: "idx_status")
    end
  end

  describe "#index_exists?" do
    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    context "when index exists" do
      let(:mock_result) { instance_double(ClickhouseRuby::Result, any?: true, error?: false) }

      it "returns true" do
        expect(adapter.index_exists?("events", "idx_status")).to be true
      end
    end

    context "when index does not exist" do
      let(:mock_result) { instance_double(ClickhouseRuby::Result, any?: false, error?: false) }

      it "returns false" do
        expect(adapter.index_exists?("events", "idx_nonexistent")).to be false
      end
    end
  end

  describe "#column_exists?" do
    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    context "when column exists" do
      let(:mock_result) do
        instance_double(ClickhouseRuby::Result, empty?: false, first: { "type" => "String" }, error?: false)
      end

      it "returns true" do
        expect(adapter.column_exists?("events", "status")).to be true
      end
    end

    context "when column does not exist" do
      let(:mock_result) { instance_double(ClickhouseRuby::Result, empty?: true, error?: false) }

      it "returns false" do
        expect(adapter.column_exists?("events", "nonexistent")).to be false
      end
    end
  end

  describe "#current_database" do
    let(:mock_result) do
      instance_double(ClickhouseRuby::Result, first: { "db" => "test_db" }, error?: false)
    end

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "returns the current database name" do
      expect(adapter.current_database).to eq("test_db")
    end
  end

  describe "#databases" do
    let(:mock_result) do
      instance_double(ClickhouseRuby::Result).tap do |r|
        allow(r).to receive(:map).and_return(%w[default system test_db])
        allow(r).to receive(:error?).and_return(false)
      end
    end

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "returns list of databases" do
      expect(adapter.databases).to eq(%w[default system test_db])
    end
  end

  describe "#create_database" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates CREATE DATABASE" do
      expect(mock_client).to receive(:execute).with(/CREATE DATABASE `new_db`/, anything)
      adapter.create_database("new_db")
    end

    it "includes IF NOT EXISTS when specified" do
      expect(mock_client).to receive(:execute).with(/IF NOT EXISTS/, anything)
      adapter.create_database("new_db", if_not_exists: true)
    end
  end

  describe "#drop_database" do
    let(:mock_result) { instance_double(ClickhouseRuby::Result, error?: false) }

    before do
      allow(mock_client).to receive(:execute).and_return(mock_result)
    end

    it "generates DROP DATABASE" do
      expect(mock_client).to receive(:execute).with(/DROP DATABASE `old_db`/, anything)
      adapter.drop_database("old_db")
    end

    it "includes IF EXISTS when specified" do
      expect(mock_client).to receive(:execute).with(/IF EXISTS/, anything)
      adapter.drop_database("old_db", if_exists: true)
    end
  end
end
