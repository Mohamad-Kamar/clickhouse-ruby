# frozen_string_literal: true

require "spec_helper"

# Only run these tests if ActiveRecord is available
# Guard must be at file level since constant resolution happens at parse time
return unless defined?(ActiveRecord) && defined?(ClickhouseRuby::ActiveRecord::ArelVisitor)

RSpec.describe ClickhouseRuby::ActiveRecord::ArelVisitor do
  let(:config) do
    {
      host: "localhost",
      port: 8123,
      database: "test_db",
    }
  end

  let(:adapter) { ClickhouseRuby::ActiveRecord::ConnectionAdapter.new(nil, nil, nil, config) }
  let(:visitor) { described_class.new(adapter) }

  # Helper to build SQL from Arel nodes
  def to_sql(node)
    visitor.compile(node, Arel::Collectors::SQLString.new).value
  end

  describe "DELETE statement conversion" do
    context "when table and wheres exist" do
      it "converts to ALTER TABLE DELETE" do
        table = Arel::Table.new("events")
        delete = Arel::Nodes::DeleteStatement.new
        delete.relation = table
        delete.wheres << Arel::Nodes::Equality.new(table[:id], 1)

        sql = to_sql(delete)
        expect(sql).to include("ALTER TABLE")
        expect(sql).to include("DELETE")
        expect(sql).to include("WHERE")
      end
    end

    context "when no WHERE clause" do
      it "adds WHERE 1=1" do
        table = Arel::Table.new("events")
        delete = Arel::Nodes::DeleteStatement.new
        delete.relation = table

        sql = to_sql(delete)
        expect(sql).to include("WHERE 1=1")
      end
    end
  end

  describe "UPDATE statement conversion" do
    context "when table, values, and wheres exist" do
      it "converts to ALTER TABLE UPDATE" do
        table = Arel::Table.new("events")
        update = Arel::Nodes::UpdateStatement.new
        update.relation = table
        update.values << Arel::Nodes::Assignment.new(
          Arel::Nodes::UnqualifiedColumn.new(table[:status]),
          Arel::Nodes.build_quoted("done"),
        )
        update.wheres << Arel::Nodes::Equality.new(table[:id], 1)

        sql = to_sql(update)
        expect(sql).to include("ALTER TABLE")
        expect(sql).to include("UPDATE")
        expect(sql).to include("status")
        expect(sql).to include("WHERE")
      end
    end

    context "when no WHERE clause" do
      it "adds WHERE 1=1" do
        table = Arel::Table.new("events")
        update = Arel::Nodes::UpdateStatement.new
        update.relation = table
        update.values << Arel::Nodes::Assignment.new(
          Arel::Nodes::UnqualifiedColumn.new(table[:status]),
          Arel::Nodes.build_quoted("done"),
        )

        sql = to_sql(update)
        expect(sql).to include("WHERE 1=1")
      end
    end
  end

  describe "LIMIT clause" do
    it "generates LIMIT clause" do
      limit = Arel::Nodes::Limit.new(10)
      sql = to_sql(limit)
      expect(sql).to eq("LIMIT 10")
    end
  end

  describe "OFFSET clause" do
    it "generates OFFSET clause" do
      offset = Arel::Nodes::Offset.new(5)
      sql = to_sql(offset)
      expect(sql).to eq("OFFSET 5")
    end
  end

  describe "Boolean values" do
    it "converts True to 1" do
      sql = to_sql(Arel::Nodes::True.new)
      expect(sql).to eq("1")
    end

    it "converts False to 0" do
      sql = to_sql(Arel::Nodes::False.new)
      expect(sql).to eq("0")
    end
  end

  describe "Table alias" do
    it "uses AS keyword" do
      table = Arel::Table.new("events")
      aliased = Arel::Nodes::TableAlias.new(table, "e")
      sql = to_sql(aliased)
      expect(sql).to include("AS")
      expect(sql).to include("`e`")
    end
  end

  describe "Aggregate functions" do
    let(:table) { Arel::Table.new("events") }

    describe "COUNT" do
      it "generates count()" do
        count = Arel::Nodes::Count.new([table[:id]])
        sql = to_sql(count)
        expect(sql).to match(/count\(.*id.*\)/i)
      end

      it "handles DISTINCT" do
        count = Arel::Nodes::Count.new([table[:id]], true)
        sql = to_sql(count)
        expect(sql).to include("DISTINCT")
      end
    end

    describe "SUM" do
      it "generates sum()" do
        sum = Arel::Nodes::Sum.new([table[:amount]])
        sql = to_sql(sum)
        expect(sql).to match(/sum\(.*amount.*\)/i)
      end
    end

    describe "AVG" do
      it "generates avg()" do
        avg = Arel::Nodes::Avg.new([table[:amount]])
        sql = to_sql(avg)
        expect(sql).to match(/avg\(.*amount.*\)/i)
      end
    end

    describe "MIN" do
      it "generates min()" do
        min = Arel::Nodes::Min.new([table[:amount]])
        sql = to_sql(min)
        expect(sql).to match(/min\(.*amount.*\)/i)
      end
    end

    describe "MAX" do
      it "generates max()" do
        max = Arel::Nodes::Max.new([table[:amount]])
        sql = to_sql(max)
        expect(sql).to match(/max\(.*amount.*\)/i)
      end
    end
  end

  describe "ORDER BY" do
    let(:table) { Arel::Table.new("events") }

    it "generates ASC" do
      asc = Arel::Nodes::Ascending.new(table[:created_at])
      sql = to_sql(asc)
      expect(sql).to include("ASC")
    end

    it "generates DESC" do
      desc = Arel::Nodes::Descending.new(table[:created_at])
      sql = to_sql(desc)
      expect(sql).to include("DESC")
    end

    it "generates NULLS FIRST" do
      nulls_first = Arel::Nodes::NullsFirst.new(table[:created_at])
      sql = to_sql(nulls_first)
      expect(sql).to include("NULLS FIRST")
    end

    it "generates NULLS LAST" do
      nulls_last = Arel::Nodes::NullsLast.new(table[:created_at])
      sql = to_sql(nulls_last)
      expect(sql).to include("NULLS LAST")
    end
  end

  describe "INSERT statement" do
    let(:table) { Arel::Table.new("events") }

    it "generates INSERT INTO" do
      insert = Arel::Nodes::InsertStatement.new
      insert.relation = table
      insert.columns << table[:id]
      insert.values = Arel::Nodes::Values.new([1])

      sql = to_sql(insert)
      expect(sql).to include("INSERT INTO")
      expect(sql).to include("VALUES")
    end
  end

  describe "Named functions" do
    it "generates function calls" do
      func = Arel::Nodes::NamedFunction.new("NOW", [])
      sql = to_sql(func)
      expect(sql).to eq("NOW()")
    end

    it "includes arguments" do
      func = Arel::Nodes::NamedFunction.new("COALESCE", [
        Arel::Nodes.build_quoted(nil),
        Arel::Nodes.build_quoted("default"),
      ],)
      sql = to_sql(func)
      expect(sql).to include("COALESCE")
    end

    it "includes alias" do
      func = Arel::Nodes::NamedFunction.new("NOW", [])
      func.alias = "current_time"
      sql = to_sql(func)
      expect(sql).to include("AS")
      expect(sql).to include("`current_time`")
    end
  end

  describe "DISTINCT" do
    it "generates DISTINCT" do
      distinct = Arel::Nodes::Distinct.new
      sql = to_sql(distinct)
      expect(sql).to eq("DISTINCT")
    end
  end

  describe "GROUP BY" do
    let(:table) { Arel::Table.new("events") }

    it "generates group expression" do
      group = Arel::Nodes::Group.new(table[:status])
      sql = to_sql(group)
      expect(sql).to include("status")
    end
  end

  describe "HAVING" do
    let(:table) { Arel::Table.new("events") }

    it "generates HAVING clause" do
      having = Arel::Nodes::Having.new(
        Arel::Nodes::GreaterThan.new(
          Arel::Nodes::Count.new([table[:id]]),
          10,
        ),
      )
      sql = to_sql(having)
      expect(sql).to include("HAVING")
    end
  end

  describe "CASE expression" do
    it "generates CASE statement" do
      case_node = Arel::Nodes::Case.new
      case_node.default = Arel::Nodes.build_quoted("unknown")

      sql = to_sql(case_node)
      expect(sql).to include("CASE")
      expect(sql).to include("ELSE")
      expect(sql).to include("END")
    end
  end
end
