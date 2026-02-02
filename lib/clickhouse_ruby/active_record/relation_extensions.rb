# frozen_string_literal: true

module ClickhouseRuby
  module ActiveRecord
    # Extensions to ActiveRecord::Relation for ClickHouse-specific query methods
    #
    # This module adds support for ClickHouse-specific clauses that aren't part of standard
    # ActiveRecord, such as PREWHERE, FINAL, SAMPLE, and SETTINGS.
    #
    # These methods are mixed into ActiveRecord::Relation via the ConnectionAdapter
    # when a ClickHouse connection is established.
    #
    # @example PREWHERE usage
    #   Event.prewhere(date: Date.today).where(status: 'active')
    #   # SELECT * FROM events PREWHERE date = '2024-01-31' WHERE status = 'active'
    #
    module RelationExtensions
      extend ::ActiveSupport::Concern

      # PREWHERE clause support
      #
      # Filters data at an earlier stage than WHERE for better query optimization.
      # ClickHouse reads only the columns needed for PREWHERE, applies the filter,
      # then reads remaining columns for WHERE processing.
      #
      # Can be called with:
      # - Hash conditions: `prewhere(active: true, status: 'done')`
      # - String conditions: `prewhere('date > ?', date)`
      # - Arel nodes: `prewhere(arel_expr)`
      # - Chain syntax: `prewhere.not(deleted: true)`
      #
      # @param opts [Hash, String, Arel::Nodes::Node, Symbol] the conditions
      # @param rest [Array] bind parameters for string conditions
      # @return [ActiveRecord::Relation] self for chaining, or PrewhereChain if opts == :chain
      def prewhere(opts = :chain, *rest)
        case opts
        when :chain
          PrewhereChain.new(spawn)
        when nil, false
          self
        else
          spawn.prewhere!(opts, *rest)
        end
      end

      # Internal method to apply prewhere conditions
      #
      # @param opts [Hash, String, Arel::Nodes::Node] the conditions
      # @param rest [Array] bind parameters
      # @return [ActiveRecord::Relation] self
      def prewhere!(opts, *rest)
        @prewhere_values ||= []

        case opts
        when String
          @prewhere_values << Arel.sql(sanitize_sql_array([opts, *rest]))
        when Hash
          opts.each do |key, value|
            @prewhere_values << build_prewhere_condition(key, value)
          end
        when Arel::Nodes::Node
          @prewhere_values << opts
        end

        self
      end

      # Get the accumulated prewhere conditions
      #
      # @return [Array] array of prewhere condition nodes
      def prewhere_values
        @prewhere_values || []
      end

      private

      # Build a prewhere condition from a column and value
      #
      # Handles different value types:
      # - nil: column IS NULL
      # - Array: column IN (values)
      # - Range: column BETWEEN start AND end
      # - Other: column = value
      #
      # @param column [Symbol, String] the column name
      # @param value [Object] the value to filter by
      # @return [Arel::Nodes::Node] the condition node
      def build_prewhere_condition(column, value)
        arel_table = self.arel_table

        case value
        when nil
          arel_table[column].eq(nil)
        when Array
          arel_table[column].in(value)
        when Range
          arel_table[column].between(value)
        else
          arel_table[column].eq(value)
        end
      end

      # Normalize settings hash
      #
      # Converts:
      # - Keys to strings
      # - Ruby true/false to 1/0
      #
      # @param opts [Hash] the raw settings
      # @return [Hash] normalized settings
      def normalize_settings(opts)
        opts.transform_keys(&:to_s).transform_values do |value|
          case value
          when true then 1
          when false then 0
          else value
          end
        end
      end

      # Format a setting value for SQL
      #
      # Converts:
      # - Strings: wrapped in single quotes
      # - Other values: converted via to_s
      #
      # @param value [Object] the setting value
      # @return [String] the formatted value
      def format_setting_value(value)
        case value
        when String
          "'#{value}'"
        else
          value.to_s
        end
      end

      # SAMPLE clause support
      #
      # Queries a subset of data for approximate results with faster execution.
      # SAMPLE allows you to explore large datasets or run approximate aggregations.
      #
      # Syntax variants:
      # - Fractional: `sample(0.1)` for 10% of data
      # - Absolute: `sample(10000)` for at least 10,000 rows
      # - With offset: `sample(0.1, offset: 0.5)` for reproducible subsets
      #
      # Can be called with:
      # - Float between 0 and 1: `sample(0.1)` (fraction of data)
      # - Integer >= 1: `sample(10000)` (at least n rows)
      # - With offset: `sample(0.1, offset: 0.5)` (fraction with offset)
      #
      # Important: Table must be created with SAMPLE BY clause!
      # ```sql
      # CREATE TABLE events (id UInt64, ...) ENGINE = MergeTree()
      # SAMPLE BY intHash32(id)
      # ORDER BY id
      # ```
      #
      # @param ratio_or_rows [Float, Integer] sampling ratio (0 < x <= 1) or min row count
      # @param offset [Float, Integer, nil] optional offset for deterministic subsets
      # @return [ActiveRecord::Relation] self for chaining
      #
      # @example Fractional sampling (10% of data)
      #   Event.sample(0.1).limit(100)
      #   # SELECT * FROM events SAMPLE 0.1 LIMIT 100
      #
      # @example Absolute sampling (at least 10,000 rows)
      #   Event.sample(10000).average(:amount)
      #   # SELECT avg(amount) FROM events SAMPLE 10000
      #
      # @example Sample with offset (reproducible subsets)
      #   Event.sample(0.1, offset: 0.5).where(status: 'done')
      #   # SELECT * FROM events SAMPLE 0.1 OFFSET 0.5 WHERE status = 'done'
      def sample(ratio_or_rows, offset: nil)
        spawn.sample!(ratio_or_rows, offset: offset)
      end

      # Internal method to apply sample
      #
      # @param ratio_or_rows [Float, Integer] sampling ratio or min row count
      # @param offset [Float, Integer, nil] optional offset
      # @return [ActiveRecord::Relation] self
      def sample!(ratio_or_rows, offset: nil)
        @sample_value = ratio_or_rows
        @sample_offset = offset
        self
      end

      # Get the sample value
      #
      # @return [Float, Integer, nil] the sample ratio or row count
      def sample_value
        @sample_value
      end

      # Get the sample offset
      #
      # @return [Float, Integer, nil] the sample offset
      def sample_offset
        @sample_offset
      end

      # SETTINGS clause support
      #
      # Per-query configuration for ClickHouse execution parameters
      #
      # Can be called with:
      # - Hash settings: `settings(max_execution_time: 60, max_threads: 4)`
      # - Multiple calls (settings merge): `settings(max_threads: 4).settings(async_insert: true)`
      #
      # @param opts [Hash] the settings as key-value pairs
      # @return [ActiveRecord::Relation] a new relation with settings applied
      #
      # @example
      #   Event.settings(max_execution_time: 60)
      #   Event.settings(max_threads: 4, async_insert: true)
      #   Event.settings(max_execution_time: 60).where(active: true)
      def settings(opts = {})
        spawn.settings!(opts)
      end

      # Internal method to apply settings (mutating)
      #
      # @param opts [Hash] the settings as key-value pairs
      # @return [ActiveRecord::Relation] self
      #
      # @private
      def settings!(opts)
        @query_settings ||= {}
        @query_settings.merge!(normalize_settings(opts))
        self
      end

      # Get current query settings
      #
      # @return [Hash] the query settings
      #
      # @private
      def query_settings
        @query_settings || {}
      end

      # Get SETTINGS clause for SQL generation
      #
      # @return [String, nil] the SETTINGS clause or nil if no settings
      #
      # @private
      def settings_clause
        return nil if query_settings.empty?

        pairs = query_settings.map do |key, value|
          "#{key} = #{format_setting_value(value)}"
        end

        "SETTINGS #{pairs.join(", ")}"
      end

      # FINAL modifier support
      #
      # Forces ClickHouse to merge data at query time for deduplication.
      # Applies to ReplacingMergeTree, CollapsingMergeTree, SummingMergeTree,
      # AggregatingMergeTree, and VersionedCollapsingMergeTree.
      #
      # Warning: FINAL forces merge during query execution, which can be 2-10x slower.
      # Use only when accuracy is critical; otherwise accept eventual consistency.
      #
      # When combined with prewhere, automatically adds required settings:
      # - optimize_move_to_prewhere = 1
      # - optimize_move_to_prewhere_if_final = 1
      #
      # @return [ActiveRecord::Relation] a new relation with FINAL modifier applied
      #
      # @example Basic FINAL usage
      #   User.final
      #   # SELECT * FROM users FINAL
      #
      # @example FINAL with WHERE
      #   User.final.where(active: true)
      #   # SELECT * FROM users FINAL WHERE active = 1
      #
      # @example FINAL with PREWHERE (auto-adds settings)
      #   User.final.prewhere(created_at: Date.today..)
      #   # SELECT * FROM users FINAL PREWHERE ...
      #   # SETTINGS optimize_move_to_prewhere = 1, optimize_move_to_prewhere_if_final = 1
      def final
        spawn.final!
      end

      # Internal method to apply FINAL modifier (mutating)
      #
      # @return [ActiveRecord::Relation] self
      #
      # @private
      def final!
        @use_final = true

        # Auto-add required settings when combining with prewhere
        if prewhere_values.any?
          @query_settings ||= {}
          @query_settings["optimize_move_to_prewhere"] = 1
          @query_settings["optimize_move_to_prewhere_if_final"] = 1
        end

        self
      end

      # Check if FINAL modifier is applied
      #
      # @return [Boolean] true if FINAL modifier is active
      #
      # @private
      def final?
        @use_final || false
      end

      # Remove FINAL modifier from the relation
      #
      # Useful for building subqueries that shouldn't include FINAL.
      #
      # @return [ActiveRecord::Relation] a new relation without FINAL
      #
      # @example
      #   relation = User.final.where(active: true)
      #   subquery = relation.unscope_final
      #   # SELECT * FROM users WHERE active = 1 (no FINAL)
      def unscope_final
        spawn.tap { |r| r.instance_variable_set(:@use_final, false) }
      end

      # Override build_arel to attach ClickHouse-specific state to the Arel AST
      #
      # This allows the ArelVisitor to access FINAL, SAMPLE, PREWHERE, and SETTINGS
      # state when generating SQL.
      #
      # @return [Arel::SelectManager]
      def build_arel(*)
        arel = super

        # Attach ClickHouse-specific state to the Arel statement
        if arel.ast.is_a?(Arel::Nodes::SelectStatement)
          arel.ast.instance_variable_set(:@clickhouse_final, @use_final)
          arel.ast.instance_variable_set(:@clickhouse_sample_value, @sample_value)
          arel.ast.instance_variable_set(:@clickhouse_sample_offset, @sample_offset)
          arel.ast.instance_variable_set(:@clickhouse_prewhere_values, @prewhere_values)
          arel.ast.instance_variable_set(:@clickhouse_query_settings, @query_settings)
        end

        arel
      end

      # Chain object for prewhere.not syntax
      #
      # Allows negation of prewhere conditions:
      #   Model.prewhere.not(deleted: true)
      #   # PREWHERE NOT(deleted = 1)
      #
      class PrewhereChain
        def initialize(relation)
          @relation = relation
        end

        # Negate the prewhere conditions
        #
        # @param opts [Hash, String, Arel::Nodes::Node] the conditions to negate
        # @param rest [Array] bind parameters
        # @return [ActiveRecord::Relation] the relation with negated prewhere
        def not(opts, *rest)
          condition_to_negate = case opts
                                when Hash
                                  build_combined_condition(opts)
                                when String
                                  Arel.sql(@relation.sanitize_sql_array([opts, *rest]))
                                else
                                  opts
                                end

          negated = Arel::Nodes::Not.new(condition_to_negate)
          @relation.prewhere!(negated)
        end

        private

        def build_combined_condition(opts)
          conditions = opts.map do |key, value|
            @relation.send(:build_prewhere_condition, key, value)
          end

          if conditions.size == 1
            conditions.first
          else
            Arel::Nodes::And.new(conditions)
          end
        end
      end
    end
  end
end
