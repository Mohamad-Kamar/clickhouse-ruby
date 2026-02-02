# frozen_string_literal: true

require "arel/visitors/to_sql"

module ClickhouseRuby
  module ActiveRecord
    # Custom Arel visitor for generating ClickHouse-specific SQL
    #
    # ClickHouse has unique requirements for certain SQL operations:
    # - DELETE: Uses ALTER TABLE ... DELETE WHERE syntax
    # - UPDATE: Uses ALTER TABLE ... UPDATE ... WHERE syntax
    # - LIMIT: Must come after ORDER BY
    # - No OFFSET without LIMIT (use LIMIT n, m syntax)
    #
    # @example DELETE conversion
    #   # Standard SQL: DELETE FROM events WHERE id = 1
    #   # ClickHouse:   ALTER TABLE events DELETE WHERE id = 1
    #
    # @example UPDATE conversion
    #   # Standard SQL: UPDATE events SET status = 'done' WHERE id = 1
    #   # ClickHouse:   ALTER TABLE events UPDATE status = 'done' WHERE id = 1
    #
    class ArelVisitor < ::Arel::Visitors::ToSql
      # Initialize the visitor
      #
      # @param connection [ConnectionAdapter] the database connection
      def initialize(connection)
        super(connection)
        @connection = connection
      end

      private

      # Visit a DELETE statement
      # Converts to ClickHouse ALTER TABLE ... DELETE WHERE syntax
      #
      # @param o [Arel::Nodes::DeleteStatement] the delete node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_DeleteStatement(o, collector)
        # Get table name
        table = o.relation

        # Build ClickHouse DELETE syntax
        collector << "ALTER TABLE "
        collector = visit(table, collector)
        collector << " DELETE"

        # Add WHERE clause (required for ClickHouse DELETE)
        if o.wheres.any?
          collector << " WHERE "
          collector = inject_join(o.wheres, collector, " AND ")
        else
          # ClickHouse requires WHERE clause for DELETE
          # Use 1=1 to delete all rows
          collector << " WHERE 1=1"
        end

        collector
      end

      # Visit an UPDATE statement
      # Converts to ClickHouse ALTER TABLE ... UPDATE ... WHERE syntax
      #
      # @param o [Arel::Nodes::UpdateStatement] the update node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_UpdateStatement(o, collector)
        # Get table name
        table = o.relation

        # Build ClickHouse UPDATE syntax
        collector << "ALTER TABLE "
        collector = visit(table, collector)
        collector << " UPDATE "

        # Add SET assignments
        collector = inject_join(o.values, collector, ", ") unless o.values.empty?

        # Add WHERE clause (required for ClickHouse UPDATE)
        if o.wheres.any?
          collector << " WHERE "
          collector = inject_join(o.wheres, collector, " AND ")
        else
          # ClickHouse requires WHERE clause for UPDATE
          collector << " WHERE 1=1"
        end

        collector
      end

      # Visit a SELECT statement
      # Ensures proper ordering of ClickHouse-specific clauses
      #
      # Clause ordering for ClickHouse:
      # SELECT ... FROM table [FINAL] [SAMPLE n] [PREWHERE ...] [WHERE ...] [GROUP BY ...] [ORDER BY ...] [LIMIT n]
      #
      # @param o [Arel::Nodes::SelectStatement] the select node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_SelectStatement(o, collector)
        collector = visit_Arel_Nodes_SelectCore(o.cores[0], collector)

        # FROM clause
        collector = visit(o.cores[0].source, collector) if o.cores[0].source

        # Get ClickHouse-specific state from the Arel node (set by RelationExtensions#build_arel)
        use_final = o.instance_variable_get(:@clickhouse_final)
        sample_value = o.instance_variable_get(:@clickhouse_sample_value)
        sample_offset = o.instance_variable_get(:@clickhouse_sample_offset)
        prewhere_values = o.instance_variable_get(:@clickhouse_prewhere_values)
        query_settings = o.instance_variable_get(:@clickhouse_query_settings)

        # FINAL clause (if set)
        collector << " FINAL" if use_final

        # SAMPLE clause (if set)
        if sample_value
          collector << " SAMPLE "
          collector << format_sample_value(sample_value)
          if sample_offset
            collector << " OFFSET "
            collector << sample_offset.to_s
          end
        end

        # PREWHERE clause (if set)
        if prewhere_values&.any?
          collector << " PREWHERE "
          collector = visit_prewhere_conditions(prewhere_values, collector)
        end

        # WHERE clause
        if o.cores[0].wheres.any?
          collector << " WHERE "
          collector = inject_join(o.cores[0].wheres, collector, " AND ")
        end

        # GROUP BY, HAVING, ORDER BY, LIMIT, OFFSET
        collector = visit_orders_and_limits(o, collector)

        # SETTINGS clause (at the very end)
        if query_settings&.any?
          collector << " "
          collector << build_settings_clause(query_settings)
        end

        collector
      end

      # Visit a LIMIT node
      # ClickHouse supports LIMIT with optional OFFSET
      #
      # @param o [Arel::Nodes::Limit] the limit node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Limit(o, collector)
        collector << "LIMIT "
        visit(o.expr, collector)
      end

      # Visit an OFFSET node
      # ClickHouse uses OFFSET after LIMIT (LIMIT n OFFSET m)
      #
      # @param o [Arel::Nodes::Offset] the offset node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Offset(o, collector)
        collector << "OFFSET "
        visit(o.expr, collector)
      end

      # Visit a SelectStatement
      # Ensures proper ordering of clauses for ClickHouse
      #
      # @param o [Arel::Nodes::SelectStatement] the select node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL

      # Visit a table alias
      # ClickHouse uses AS keyword for table aliases
      #
      # @param o [Arel::Nodes::TableAlias] the table alias node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_TableAlias(o, collector)
        collector = visit(o.relation, collector)
        collector << " AS "
        collector << quote_table_name(o.name)
      end

      # Quote a table name using the connection's quoting
      #
      # @param name [String] the table name
      # @return [String] the quoted table name
      def quote_table_name(name)
        @connection.quote_table_name(name)
      end

      # Quote a column name using the connection's quoting
      #
      # @param name [String] the column name
      # @return [String] the quoted column name
      def quote_column_name(name)
        @connection.quote_column_name(name)
      end

      # Visit a True node
      #
      # @param o [Arel::Nodes::True] the true node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_True(_o, collector)
        collector << "1"
      end

      # Visit a False node
      #
      # @param o [Arel::Nodes::False] the false node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_False(_o, collector)
        collector << "0"
      end

      # Visit a CASE statement
      #
      # @param o [Arel::Nodes::Case] the case node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Case(o, collector)
        collector << "CASE "

        if o.case
          visit(o.case, collector)
          collector << " "
        end

        o.conditions.each do |condition|
          visit(condition, collector)
          collector << " "
        end

        if o.default
          collector << "ELSE "
          visit(o.default, collector)
          collector << " "
        end

        collector << "END"
      end

      # Handle INSERT statements
      # ClickHouse uses standard INSERT syntax but with some differences
      #
      # @param o [Arel::Nodes::InsertStatement] the insert node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_InsertStatement(o, collector)
        collector << "INSERT INTO "
        collector = visit(o.relation, collector)

        if o.columns.any?
          collector << " ("
          o.columns.each_with_index do |column, i|
            collector << ", " if i.positive?
            collector << quote_column_name(column.name)
          end
          collector << ")"
        end

        if o.values
          collector << " VALUES "
          collector = visit(o.values, collector)
        elsif o.select
          collector << " "
          collector = visit(o.select, collector)
        end

        collector
      end

      # Handle VALUES list
      #
      # @param o [Arel::Nodes::Values] the values node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Values(o, collector)
        collector << "("
        o.expressions.each_with_index do |expr, i|
          collector << ", " if i.positive?
          case expr
          when Arel::Nodes::SqlLiteral
            collector << expr.to_s
          when nil
            collector << "NULL"
          else
            collector = visit(expr, collector)
          end
        end
        collector << ")"
      end

      # Handle multiple VALUES rows for bulk insert
      #
      # @param o [Arel::Nodes::ValuesList] the values list node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_ValuesList(o, collector)
        o.rows.each_with_index do |row, i|
          collector << ", " if i.positive?
          collector << "("
          row.each_with_index do |value, j|
            collector << ", " if j.positive?
            case value
            when Arel::Nodes::SqlLiteral
              collector << value.to_s
            when nil
              collector << "NULL"
            else
              collector = visit(value, collector)
            end
          end
          collector << ")"
        end
        collector
      end

      # Handle assignment for UPDATE statements
      #
      # @param o [Arel::Nodes::Assignment] the assignment node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Assignment(o, collector)
        case o.left
        when Arel::Nodes::UnqualifiedColumn, Arel::Attributes::Attribute
          collector << quote_column_name(o.left.name)
        else
          collector = visit(o.left, collector)
        end

        collector << " = "

        case o.right
        when nil
          collector << "NULL"
        else
          collector = visit(o.right, collector)
        end

        collector
      end

      # Handle named functions
      #
      # @param o [Arel::Nodes::NamedFunction] the function node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_NamedFunction(o, collector)
        collector << o.name
        collector << "("

        collector << "DISTINCT " if o.distinct

        o.expressions.each_with_index do |expr, i|
          collector << ", " if i.positive?
          collector = visit(expr, collector)
        end

        collector << ")"

        if o.alias
          collector << " AS "
          collector << quote_column_name(o.alias)
        end

        collector
      end

      # Handle DISTINCT
      #
      # @param o [Arel::Nodes::Distinct] the distinct node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Distinct(_o, collector)
        collector << "DISTINCT"
      end

      # Handle GROUP BY
      #
      # @param o [Arel::Nodes::Group] the group node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Group(o, collector)
        visit(o.expr, collector)
      end

      # Handle HAVING
      #
      # @param o [Arel::Nodes::Having] the having node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Having(o, collector)
        collector << "HAVING "
        visit(o.expr, collector)
      end

      # Handle ordering (ASC/DESC)
      #
      # @param o [Arel::Nodes::Ordering] the ordering node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Ascending(o, collector)
        collector = visit(o.expr, collector)
        collector << " ASC"
      end

      # Handle descending order
      #
      # @param o [Arel::Nodes::Descending] the descending node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Descending(o, collector)
        collector = visit(o.expr, collector)
        collector << " DESC"
      end

      # Handle NULLS FIRST
      #
      # @param o [Arel::Nodes::NullsFirst] the nulls first node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_NullsFirst(o, collector)
        collector = visit(o.expr, collector)
        collector << " NULLS FIRST"
      end

      # Handle NULLS LAST
      #
      # @param o [Arel::Nodes::NullsLast] the nulls last node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_NullsLast(o, collector)
        collector = visit(o.expr, collector)
        collector << " NULLS LAST"
      end

      # Handle COUNT function
      #
      # @param o [Arel::Nodes::Count] the count node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Count(o, collector)
        aggregate("count", o, collector)
      end

      # Handle SUM function
      #
      # @param o [Arel::Nodes::Sum] the sum node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Sum(o, collector)
        aggregate("sum", o, collector)
      end

      # Handle AVG function
      #
      # @param o [Arel::Nodes::Avg] the avg node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Avg(o, collector)
        aggregate("avg", o, collector)
      end

      # Handle MIN function
      #
      # @param o [Arel::Nodes::Min] the min node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Min(o, collector)
        aggregate("min", o, collector)
      end

      # Handle MAX function
      #
      # @param o [Arel::Nodes::Max] the max node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_Arel_Nodes_Max(o, collector)
        aggregate("max", o, collector)
      end

      # Helper to generate aggregate functions
      #
      # @param name [String] function name
      # @param o [Object] the node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def aggregate(name, o, collector)
        collector << "#{name}("
        collector << "DISTINCT " if o.distinct
        o.expressions.each_with_index do |expr, i|
          collector << ", " if i.positive?
          collector = visit(expr, collector)
        end
        collector << ")"
        if o.alias
          collector << " AS "
          collector << quote_column_name(o.alias)
        end
        collector
      end

      # Visit PREWHERE conditions
      #
      # @param conditions [Array] array of prewhere condition nodes
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_prewhere_conditions(conditions, collector)
        conditions.each_with_index do |condition, i|
          collector << " AND " if i.positive?
          collector = visit(condition, collector)
        end
        collector
      end

      # Build SETTINGS clause for SQL generation
      #
      # @param settings [Hash] the settings hash
      # @return [String] the SETTINGS clause
      def build_settings_clause(settings)
        pairs = settings.map do |key, value|
          formatted = case value
                      when String then "'#{value}'"
                      when true then "1"
                      when false then "0"
                      else value.to_s
                      end
          "#{key} = #{formatted}"
        end

        "SETTINGS #{pairs.join(", ")}"
      end

      # Visit orders and limits
      #
      # @param o [Arel::Nodes::SelectStatement] the select node
      # @param collector [Arel::Collectors::SQLString] SQL collector
      # @return [Arel::Collectors::SQLString] the collector with SQL
      def visit_orders_and_limits(o, collector)
        # GROUP BY
        if o.cores[0].groups.any?
          collector << " GROUP BY "
          collector = inject_join(o.cores[0].groups, collector, ", ")
        end

        # HAVING
        if o.cores[0].havings.any?
          collector << " HAVING "
          collector = inject_join(o.cores[0].havings, collector, " AND ")
        end

        # ORDER BY
        if o.orders.any?
          collector << " ORDER BY "
          collector = inject_join(o.orders, collector, ", ")
        end

        # LIMIT
        if o.limit
          collector << " "
          collector = visit(o.limit, collector)
        end

        # OFFSET
        if o.offset
          collector << " "
          collector = visit(o.offset, collector)
        end

        collector
      end

      # Format a sample value for SQL generation
      #
      # Handles differentiation between Integer (absolute row count) and Float (fractional).
      # Ruby's to_s preserves the distinction: Integer 1 becomes "1", Float 1.0 becomes "1.0"
      # This matters because SAMPLE 1 means "at least 1 row" while SAMPLE 1.0 means "100% of data".
      #
      # @param value [Float, Integer] the sample value
      # @return [String] the formatted sample value
      def format_sample_value(value)
        value.to_s
      end
    end
  end
end
