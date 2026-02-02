# frozen_string_literal: true

require "spec_helper"

# Only run these tests if ActiveRecord is available
return unless defined?(ActiveRecord) && defined?(ClickhouseRuby::ActiveRecord)

RSpec.describe "PREWHERE support" do
  let(:model) do
    Class.new(ClickhouseRuby::ActiveRecord::Base) do
      self.table_name = "events"
    end
  end

  describe "#prewhere" do
    context "returns relation" do
      it "returns a chainable relation" do
        relation = model.prewhere(active: true)
        expect(relation).to be_a(::ActiveRecord::Relation)
        expect(relation.model).to eq(model)
      end
    end

    context "hash conditions" do
      it "generates PREWHERE clause with hash" do
        sql = model.prewhere(active: true).to_sql
        expect(sql).to include("PREWHERE")
        expect(sql).to include("active")
      end

      it "handles multiple hash keys" do
        sql = model.prewhere(active: true, status: "done").to_sql
        expect(sql).to include("PREWHERE")
        expect(sql).to match(/active.*AND.*status|status.*AND.*active/)
      end
    end

    context "string conditions" do
      it "generates PREWHERE clause with string" do
        sql = model.prewhere("date > '2024-01-01'").to_sql
        expect(sql).to include("PREWHERE")
        expect(sql).to include("date > '2024-01-01'")
      end
    end

    context "placeholders" do
      it "accepts string with placeholders" do
        date = "2024-01-01"
        sql = model.prewhere("date > ?", date).to_sql
        expect(sql).to include("PREWHERE")
        expect(sql).to include("2024-01-01")
      end

      it "handles multiple placeholders" do
        sql = model.prewhere("date > ? AND amount < ?", "2024-01-01", 100).to_sql
        expect(sql).to include("PREWHERE")
        expect(sql).to include("2024-01-01")
        expect(sql).to include("100")
      end
    end

    context "SQL ordering" do
      it "places PREWHERE before WHERE" do
        sql = model.prewhere(active: true).where(status: "done").to_sql

        prewhere_pos = sql.index("PREWHERE")
        where_pos = sql.index("WHERE")

        expect(prewhere_pos).to be_present
        expect(where_pos).to be_present
        expect(prewhere_pos).to be < where_pos
      end
    end

    context "multiple prewhere" do
      it "ANDs multiple prewhere conditions" do
        sql = model.prewhere(active: true).prewhere(deleted: false).to_sql
        expect(sql).to include("PREWHERE")
        expect(sql).to match(/PREWHERE.*AND/)
      end
    end

    context "chain with where" do
      it "chains prewhere with where" do
        sql = model.prewhere(active: true).where(category: "sales").to_sql

        expect(sql).to include("PREWHERE")
        expect(sql).to include("WHERE")
        expect(sql).to include("active")
        expect(sql).to include("category")
      end

      it "chains with where and other query methods" do
        sql = model.prewhere(active: true)
             .where(category: "sales")
             .order(created_at: :desc)
             .limit(10)
             .to_sql

        expect(sql).to include("PREWHERE")
        expect(sql).to include("WHERE")
        expect(sql).to include("ORDER BY")
        expect(sql).to include("LIMIT")
      end
    end

    context "prewhere not" do
      it "supports prewhere.not syntax" do
        sql = model.prewhere.not(deleted: true).to_sql
        expect(sql).to include("PREWHERE")
        expect(sql).to include("NOT")
      end
    end

    context "with IN conditions" do
      it "supports IN conditions" do
        sql = model.prewhere(status: ["a", "b", "c"]).to_sql
        expect(sql).to include("IN")
      end
    end

    context "with range conditions" do
      it "supports range conditions" do
        sql = model.prewhere(id: 1..100).to_sql
        expect(sql).to include("BETWEEN")
      end
    end

    context "with nil conditions" do
      it "handles nil values" do
        sql = model.prewhere(status: nil).to_sql
        expect(sql).to include("PREWHERE")
        expect(sql).to include("status")
      end
    end

    context "blank prewhere" do
      it "returns self when prewhere called with no args" do
        relation = model.prewhere
        expect(relation).to be_a(::ActiveRecord::Relation)
      end
    end
  end
end
