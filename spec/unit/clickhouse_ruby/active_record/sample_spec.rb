# frozen_string_literal: true

require "spec_helper"

# Only run these tests if ActiveRecord is available
return unless defined?(ActiveRecord) && defined?(ClickhouseRuby::ActiveRecord)

RSpec.describe "SAMPLE clause" do
  let(:model) do
    Class.new(ClickhouseRuby::ActiveRecord::Base) do
      self.table_name = "events"
    end
  end

  describe "#sample" do
    context "with fractional value" do
      it "generates SAMPLE with float" do
        sql = model.sample(0.1).to_sql
        expect(sql).to include("SAMPLE 0.1")
      end

      it "accepts fractional sampling" do
        relation = model.sample(0.1)
        expect(relation).to be_a(::ActiveRecord::Relation)
        expect(relation.model).to eq(model)
      end
    end

    context "with absolute value" do
      it "generates SAMPLE with integer" do
        sql = model.sample(10000).to_sql
        expect(sql).to include("SAMPLE 10000")
      end

      it "accepts absolute sampling" do
        relation = model.sample(10000)
        expect(relation).to be_a(::ActiveRecord::Relation)
        expect(relation.model).to eq(model)
      end
    end

    context "with offset" do
      it "generates SAMPLE with OFFSET" do
        sql = model.sample(0.1, offset: 0.5).to_sql
        expect(sql).to include("SAMPLE 0.1 OFFSET 0.5")
      end

      it "accepts offset parameter" do
        relation = model.sample(0.1, offset: 0.5)
        expect(relation).to be_a(::ActiveRecord::Relation)
      end
    end

    context "integer 1 vs float 1.0" do
      it "treats integer 1 as \"at least 1 row\"" do
        sql = model.sample(1).to_sql
        expect(sql).to include("SAMPLE 1")
        expect(sql).not_to include("SAMPLE 1.0")
      end

      it "treats float 1.0 as \"100% of data\"" do
        sql = model.sample(1.0).to_sql
        expect(sql).to include("SAMPLE 1.0")
      end
    end
  end

  describe "SQL generation" do
    context "SQL fractional" do
      it "generates SAMPLE with fractional value" do
        sql = model.sample(0.1).to_sql
        expect(sql).to include("SAMPLE 0.1")
      end
    end

    context "SQL absolute" do
      it "generates SAMPLE with absolute count" do
        sql = model.sample(10000).to_sql
        expect(sql).to include("SAMPLE 10000")
      end
    end

    context "SQL offset" do
      it "generates SAMPLE with OFFSET clause" do
        sql = model.sample(0.1, offset: 0.5).to_sql
        expect(sql).to include("SAMPLE 0.1 OFFSET 0.5")
      end

      it "allows offset with integer sample" do
        sql = model.sample(100, offset: 0.5).to_sql
        expect(sql).to include("SAMPLE 100 OFFSET 0.5")
      end
    end

    context "SQL position" do
      it "places SAMPLE after FINAL" do
        sql = model.final.sample(0.1).to_sql

        final_pos = sql.index("FINAL")
        sample_pos = sql.index("SAMPLE")

        expect(final_pos).to be_present
        expect(sample_pos).to be_present
        expect(final_pos).to be < sample_pos
      end

      it "places SAMPLE before PREWHERE" do
        sql = model.sample(0.1).prewhere(active: true).to_sql

        sample_pos = sql.index("SAMPLE")
        prewhere_pos = sql.index("PREWHERE")

        expect(sample_pos).to be_present
        expect(prewhere_pos).to be_present
        expect(sample_pos).to be < prewhere_pos
      end

      it "places SAMPLE before WHERE" do
        sql = model.sample(0.1).where(status: "done").to_sql

        sample_pos = sql.index("SAMPLE")
        where_pos = sql.index("WHERE")

        expect(sample_pos).to be_present
        expect(where_pos).to be_present
        expect(sample_pos).to be < where_pos
      end
    end
  end

  describe "chainability" do
    context "chainable" do
      it "chains with where" do
        sql = model.sample(0.1).where(active: true).to_sql
        expect(sql).to include("SAMPLE 0.1")
        expect(sql).to include("WHERE")
      end

      it "chains with limit" do
        sql = model.sample(0.1).limit(100).to_sql
        expect(sql).to include("SAMPLE 0.1")
        expect(sql).to include("LIMIT 100")
      end

      it "chains with order" do
        sql = model.sample(0.1).order(created_at: :desc).to_sql
        expect(sql).to include("SAMPLE 0.1")
        expect(sql).to include("ORDER BY")
      end

      it "chains with multiple methods" do
        sql = model.sample(0.1).where(active: true).order(id: :asc).limit(50).to_sql
        expect(sql).to include("SAMPLE 0.1")
        expect(sql).to include("WHERE")
        expect(sql).to include("ORDER BY")
        expect(sql).to include("LIMIT")
      end
    end
  end

  describe "sample immutability" do
    it "returns a new relation when calling sample" do
      relation1 = model.sample(0.1)
      relation2 = model.sample(0.2)

      expect(relation1.to_sql).to include("SAMPLE 0.1")
      expect(relation2.to_sql).to include("SAMPLE 0.2")
    end

    it "preserves original relation when chaining" do
      original = model.sample(0.1)
      chained = original.where(status: "done")

      expect(original.to_sql).to include("SAMPLE 0.1")
      expect(chained.to_sql).to include("SAMPLE 0.1")
    end
  end
end
