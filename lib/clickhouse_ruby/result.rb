# frozen_string_literal: true

module ClickhouseRuby
  # Query result container that provides access to columns, types, and rows
  #
  # Result implements Enumerable for easy iteration over rows.
  # Each row is returned as a Hash with column names as keys and
  # properly deserialized values.
  #
  # @example Iterating over results
  #   result = client.execute('SELECT id, name FROM users')
  #   result.columns  # => ['id', 'name']
  #   result.types    # => ['UInt64', 'String']
  #
  #   result.each do |row|
  #     puts "#{row['id']}: #{row['name']}"
  #   end
  #
  # @example Array-like access
  #   result.rows[0]       # => { 'id' => 1, 'name' => 'Alice' }
  #   result.first         # => { 'id' => 1, 'name' => 'Alice' }
  #   result.to_a          # => [{ 'id' => 1, 'name' => 'Alice' }, ...]
  #
  # @example Metadata access
  #   result.count         # => 100
  #   result.empty?        # => false
  #   result.elapsed_time  # => 0.023 (seconds)
  #
  class Result
    include Enumerable

    # @return [Array<String>] column names in order
    attr_reader :columns

    # @return [Array<String>] ClickHouse type strings for each column
    attr_reader :types

    # @return [Array<Hash>] rows as hashes with column names as keys
    attr_reader :rows

    # @return [Float, nil] query execution time in seconds (from ClickHouse)
    attr_reader :elapsed_time

    # @return [Integer, nil] number of rows read by ClickHouse
    attr_reader :rows_read

    # @return [Integer, nil] bytes read by ClickHouse
    attr_reader :bytes_read

    # Creates a new Result from parsed response data
    #
    # @param columns [Array<String>] column names
    # @param types [Array<String>] ClickHouse type strings
    # @param data [Array<Array>] raw row data (values in column order)
    # @param statistics [Hash] optional query statistics from ClickHouse
    # @param deserialize [Boolean] whether to deserialize values using type system
    def initialize(columns:, types:, data:, statistics: {}, deserialize: true)
      @columns = columns.freeze
      @types = types.freeze
      @elapsed_time = statistics["elapsed"]
      @rows_read = statistics["rows_read"]
      @bytes_read = statistics["bytes_read"]

      # Build type instances for deserialization
      @type_instances = (types.map { |t| Types.lookup(t) } if deserialize)

      # Convert raw data to row hashes
      @rows = build_rows(data).freeze
    end

    # Iterates over each row
    #
    # @yield [Hash] each row as a hash
    # @return [Enumerator] if no block given
    def each(&block)
      @rows.each(&block)
    end

    # Returns the number of rows
    #
    # @return [Integer] row count
    def count
      @rows.length
    end
    alias size count
    alias length count
    alias data rows

    # Returns whether there are no rows
    #
    # @return [Boolean] true if no rows
    def empty?
      @rows.empty?
    end

    # Returns the first row
    #
    # @return [Hash, nil] the first row or nil
    def first
      @rows.first
    end

    # Returns the last row
    #
    # @return [Hash, nil] the last row or nil
    def last
      @rows.last
    end

    # Access a row by index
    #
    # @param index [Integer] row index
    # @return [Hash, nil] the row or nil
    def [](index)
      @rows[index]
    end

    # Returns a specific column's values across all rows
    #
    # @param column_name [String] the column name
    # @return [Array] values for that column
    # @raise [ArgumentError] if column doesn't exist
    def column_values(column_name)
      index = @columns.index(column_name)
      raise ArgumentError, "Unknown column: #{column_name}" if index.nil?

      @rows.map { |row| row[column_name] }
    end

    # Returns column names mapped to their types
    #
    # @return [Hash<String, String>] column name => type mapping
    def column_types
      @columns.zip(@types).to_h
    end

    # Creates an empty result (for commands that don't return data)
    #
    # @return [Result] an empty result
    def self.empty
      new(columns: [], types: [], data: [])
    end

    # Creates a result from JSONCompact format response
    #
    # @param response_data [Hash] parsed JSON response
    # @return [Result] the result
    def self.from_json_compact(response_data)
      meta = response_data["meta"] || []
      columns = meta.map { |m| m["name"] }
      types = meta.map { |m| m["type"] }
      data = response_data["data"] || []
      statistics = response_data["statistics"] || {}

      new(columns: columns, types: types, data: data, statistics: statistics)
    end

    # Returns a human-readable string representation
    #
    # @return [String] string representation
    def inspect
      "#<#{self.class.name} columns=#{@columns.inspect} rows=#{count}>"
    end

    private

    # Builds row hashes from raw data
    #
    # @param data [Array<Array>] raw row data
    # @return [Array<Hash>] rows as hashes
    def build_rows(data)
      data.map do |row_values|
        row = {}
        @columns.each_with_index do |col, i|
          value = row_values[i]
          # Deserialize if we have type instances
          value = @type_instances[i].deserialize(value) if @type_instances
          row[col] = value
        end
        row
      end
    end
  end
end
