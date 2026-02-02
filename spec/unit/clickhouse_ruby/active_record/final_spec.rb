# frozen_string_literal: true

require "spec_helper"

# Only run these tests if ActiveRecord is available
return unless defined?(ActiveRecord) && defined?(ClickhouseRuby::ActiveRecord)

RSpec.describe "FINAL modifier" do
  let(:model) do
    Class.new(ClickhouseRuby::ActiveRecord::Base) do
      self.table_name = "users"
    end
  end

  describe "#final" do
    context "method exists" do
      it "responds to final method" do
        expect(model).to respond_to(:final)
      end

      it "returns a chainable relation" do
        relation = model.final
        expect(relation).to be_a(::ActiveRecord::Relation)
        expect(relation.model).to eq(model)
      end
    end

    context "chainable" do
      it "returns a new relation" do
        original = model.all
        final_relation = model.final

        expect(final_relation).not_to equal(original)
        expect(final_relation).to be_a(::ActiveRecord::Relation)
      end

      it "allows further chaining with where" do
        relation = model.final.where(id: 1)

        expect(relation).to be_a(::ActiveRecord::Relation)
        expect(relation.to_sql).to include("FINAL")
        expect(relation.to_sql).to include("WHERE")
      end

      it "allows further chaining with prewhere" do
        relation = model.final.prewhere(active: true)

        expect(relation).to be_a(::ActiveRecord::Relation)
        expect(relation.to_sql).to include("FINAL")
        expect(relation.to_sql).to include("PREWHERE")
      end

      it "allows further chaining with order" do
        relation = model.final.order(id: :desc)

        expect(relation).to be_a(::ActiveRecord::Relation)
        expect(relation.to_sql).to include("FINAL")
        expect(relation.to_sql).to include("ORDER BY")
      end
    end

    context "chain with where" do
      it "chains final with where" do
        sql = model.final.where(id: 1).to_sql

        expect(sql).to include("FINAL")
        expect(sql).to include("WHERE")
        expect(sql).to include("id")
      end

      it "places FINAL before WHERE" do
        sql = model.final.where(id: 1).to_sql

        final_pos = sql.index("FINAL")
        where_pos = sql.index("WHERE")

        expect(final_pos).to be_present
        expect(where_pos).to be_present
        expect(final_pos).to be < where_pos
      end

      it "works with multiple where conditions" do
        sql = model.final.where(id: 1, active: true).to_sql

        expect(sql).to include("FINAL")
        expect(sql).to include("WHERE")
      end
    end

    context "chain with prewhere" do
      it "chains final with prewhere" do
        sql = model.final.prewhere(active: true).to_sql

        expect(sql).to include("FINAL")
        expect(sql).to include("PREWHERE")
        expect(sql).to include("active")
      end

      it "places FINAL before PREWHERE" do
        sql = model.final.prewhere(active: true).to_sql

        final_pos = sql.index("FINAL")
        prewhere_pos = sql.index("PREWHERE")

        expect(final_pos).to be_present
        expect(prewhere_pos).to be_present
        expect(final_pos).to be < prewhere_pos
      end

      it "places PREWHERE before WHERE" do
        sql = model.final.prewhere(active: true).where(id: 1).to_sql

        prewhere_pos = sql.index("PREWHERE")
        where_pos = sql.index("WHERE")

        expect(prewhere_pos).to be_present
        expect(where_pos).to be_present
        expect(prewhere_pos).to be < where_pos
      end
    end

    context "SQL position" do
      it "generates FINAL in SQL after table name" do
        sql = model.final.to_sql

        expect(sql).to include("FROM users FINAL")
      end

      it "generates FINAL before WHERE clause" do
        sql = model.final.where(id: 1).to_sql

        final_pos = sql.index("FINAL")
        where_pos = sql.index("WHERE")

        expect(final_pos).to be < where_pos
      end

      it "generates FINAL before PREWHERE clause" do
        sql = model.final.prewhere(active: true).to_sql

        final_pos = sql.index("FINAL")
        prewhere_pos = sql.index("PREWHERE")

        expect(final_pos).to be < prewhere_pos
      end

      it "generates FINAL before SAMPLE clause" do
        sql = model.final.sample(0.1).to_sql

        final_pos = sql.index("FINAL")
        sample_pos = sql.index("SAMPLE")

        expect(final_pos).to be < sample_pos
      end

      it "maintains correct clause order: FINAL > SAMPLE > PREWHERE > WHERE" do
        sql = model.final.sample(0.1).prewhere(active: true).where(id: 1).to_sql

        final_pos = sql.index("FINAL")
        sample_pos = sql.index("SAMPLE")
        prewhere_pos = sql.index("PREWHERE")
        where_pos = sql.index("WHERE")

        expect(final_pos).to be < sample_pos
        expect(sample_pos).to be < prewhere_pos
        expect(prewhere_pos).to be < where_pos
      end
    end
  end

  describe "#final?" do
    context "predicate" do
      it "returns false by default" do
        expect(model.all.final?).to be false
      end

      it "returns true after final called" do
        expect(model.final.final?).to be true
      end

      it "returns false when unscope_final is called" do
        expect(model.final.unscope_final.final?).to be false
      end
    end
  end

  describe "#unscope_final" do
    context "unscope" do
      it "removes FINAL modifier" do
        relation = model.final.unscope_final

        expect(relation.final?).to be false
        expect(relation.to_sql).not_to include("FINAL")
      end

      it "returns a new relation" do
        final_rel = model.final
        unscoped_rel = final_rel.unscope_final

        expect(unscoped_rel).not_to equal(final_rel)
        expect(final_rel.final?).to be true
        expect(unscoped_rel.final?).to be false
      end

      it "works with other clauses" do
        sql = model.final.where(id: 1).unscope_final.to_sql

        expect(sql).not_to include("FINAL")
        expect(sql).to include("WHERE")
      end
    end
  end

  describe "with prewhere" do
    context "prewhere settings" do
      it "auto-adds optimize_move_to_prewhere setting" do
        relation = model.final.prewhere(active: true)

        expect(relation.query_settings["optimize_move_to_prewhere"]).to eq(1)
      end

      it "auto-adds optimize_move_to_prewhere_if_final setting" do
        relation = model.final.prewhere(active: true)

        expect(relation.query_settings["optimize_move_to_prewhere_if_final"]).to eq(1)
      end

      it "auto-adds both settings together" do
        relation = model.final.prewhere(active: true)

        expect(relation.query_settings["optimize_move_to_prewhere"]).to eq(1)
        expect(relation.query_settings["optimize_move_to_prewhere_if_final"]).to eq(1)
      end

      it "does not add settings if prewhere_values is empty" do
        relation = model.final

        expect(relation.query_settings["optimize_move_to_prewhere"]).to be_nil
        expect(relation.query_settings["optimize_move_to_prewhere_if_final"]).to be_nil
      end

      it "includes settings in SQL" do
        sql = model.final.prewhere(active: true).to_sql

        expect(sql).to include("SETTINGS")
        expect(sql).to include("optimize_move_to_prewhere")
        expect(sql).to include("optimize_move_to_prewhere_if_final")
      end

      it "can chain multiple prewhere calls" do
        relation = model.final.prewhere(active: true).prewhere(deleted: false)

        expect(relation.query_settings["optimize_move_to_prewhere"]).to eq(1)
        expect(relation.query_settings["optimize_move_to_prewhere_if_final"]).to eq(1)
      end
    end
  end

  describe "complex queries" do
    it "works with aggregation" do
      sql = model.final.group(:status).count.to_sql

      expect(sql).to include("FINAL")
      expect(sql).to include("GROUP BY")
    end

    it "works with limit and offset" do
      sql = model.final.limit(10).offset(5).to_sql

      expect(sql).to include("FINAL")
      expect(sql).to include("LIMIT")
    end

    it "works with order by" do
      sql = model.final.order(id: :desc).to_sql

      expect(sql).to include("FINAL")
      expect(sql).to include("ORDER BY")
    end

    it "works with select specific columns" do
      sql = model.final.select(:id, :name).to_sql

      expect(sql).to include("FINAL")
      expect(sql).to include("SELECT")
    end

    it "works with distinct" do
      sql = model.final.distinct.to_sql

      expect(sql).to include("FINAL")
      expect(sql).to include("DISTINCT")
    end
  end

  describe "settings interaction" do
    it "can combine final with settings method" do
      relation = model.final.settings(max_execution_time: 60)

      expect(relation.final?).to be true
      expect(relation.query_settings["max_execution_time"]).to eq(60)
    end

    it "final with prewhere settings overrides existing settings" do
      relation = model.settings(max_execution_time: 60).final.prewhere(active: true)

      expect(relation.query_settings["max_execution_time"]).to eq(60)
      expect(relation.query_settings["optimize_move_to_prewhere"]).to eq(1)
      expect(relation.query_settings["optimize_move_to_prewhere_if_final"]).to eq(1)
    end
  end
end
