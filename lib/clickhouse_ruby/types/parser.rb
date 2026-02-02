# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # AST-based parser for ClickHouse type strings
    #
    # This parser correctly handles nested types like:
    # - Array(Tuple(String, UInt64))
    # - Map(String, Array(Nullable(Int32)))
    # - Nullable(LowCardinality(String))
    #
    # The parser does NOT validate types - it only handles syntax.
    # Type validation is delegated to ClickHouse.
    #
    # Grammar:
    #   type := simple_type | parameterized_type
    #   parameterized_type := identifier "(" type_list ")"
    #   type_list := type ("," type)*
    #   simple_type := identifier
    #   identifier := [a-zA-Z_][a-zA-Z0-9_]*
    #
    # @example
    #   parser = Parser.new
    #   parser.parse('String')
    #   # => { type: 'String' }
    #
    #   parser.parse('Array(UInt64)')
    #   # => { type: 'Array', args: [{ type: 'UInt64' }] }
    #
    #   parser.parse('Map(String, Array(Tuple(String, UInt64)))')
    #   # => { type: 'Map', args: [
    #   #      { type: 'String' },
    #   #      { type: 'Array', args: [
    #   #        { type: 'Tuple', args: [
    #   #          { type: 'String' },
    #   #          { type: 'UInt64' }
    #   #        ]}
    #   #      ]}
    #   #    ]}
    #
    class Parser
      # Error raised when parsing fails
      class ParseError < ClickhouseRuby::Error
        attr_reader :position, :input

        def initialize(message, position: nil, input: nil)
          @position = position
          @input = input
          full_message = position ? "#{message} at position #{position}" : message
          full_message += ": '#{input}'" if input
          super(full_message)
        end
      end

      # Parses a ClickHouse type string into an AST
      #
      # @param type_string [String] the type string to parse
      # @return [Hash] the parsed AST with :type and optional :args keys
      # @raise [ParseError] if the type string is invalid
      def parse(type_string)
        raise ParseError, "Type string cannot be nil" if type_string.nil?

        @input = type_string.strip
        @pos = 0

        raise ParseError.new("Type string cannot be empty", input: type_string) if @input.empty?

        result = parse_type
        skip_whitespace

        # Ensure we consumed the entire input
        unless @pos >= @input.length
          raise ParseError.new("Unexpected character '#{@input[@pos]}'", position: @pos, input: type_string)
        end

        result
      end

      private

      # Parses a single type (simple or parameterized) or literal value
      #
      # ClickHouse type parameters can be:
      # - Type names: String, UInt64
      # - Numeric literals: 3 (precision), 9 (scale)
      # - String literals: 'UTC' (timezone)
      # - Enum entries: 'active' = 1 (for Enum8/Enum16)
      #
      # @return [Hash] the parsed type/value
      def parse_type
        skip_whitespace

        # Handle numeric literals (e.g., DateTime64(3))
        if numeric_char?(peek)
          value = parse_numeric
          return { type: value }
        end

        # Handle string literals (e.g., DateTime64(3, 'UTC') or Enum8('active' = 1))
        if peek == "'"
          value = parse_string_literal
          skip_whitespace
          # Handle Enum value assignment: 'name' = value (or 'name' = -1)
          if peek == "="
            consume("=")
            skip_whitespace
            # Skip optional negative sign
            if peek == "-"
              @pos += 1
              skip_whitespace
            end
            # Skip the numeric value
            parse_numeric if numeric_char?(peek)
          end
          return { type: value }
        end

        name = parse_identifier

        skip_whitespace
        if peek == "("
          consume("(")
          args = parse_type_list
          consume(")")
          { type: name, args: args }
        else
          { type: name }
        end
      end

      # Parses a comma-separated list of types
      #
      # @return [Array<Hash>] the list of parsed types
      def parse_type_list
        types = []
        skip_whitespace

        # Handle empty argument list
        return types if peek == ")"

        types << parse_type

        while peek == ","
          consume(",")
          types << parse_type
        end

        types
      end

      # Parses an identifier (type name)
      #
      # @return [String] the identifier
      # @raise [ParseError] if no identifier is found
      def parse_identifier
        skip_whitespace
        start_pos = @pos

        # First character must be letter or underscore
        unless @pos < @input.length && identifier_start_char?(@input[@pos])
          raise ParseError.new("Expected type name", position: @pos, input: @input)
        end

        @pos += 1

        # Subsequent characters can be letters, digits, or underscores
        @pos += 1 while @pos < @input.length && identifier_char?(@input[@pos])

        @input[start_pos...@pos]
      end

      # Checks if a character can start an identifier
      #
      # @param char [String] the character to check
      # @return [Boolean] true if valid
      def identifier_start_char?(char)
        char =~ /[a-zA-Z_]/
      end

      # Checks if a character can be part of an identifier
      #
      # @param char [String] the character to check
      # @return [Boolean] true if valid
      def identifier_char?(char)
        char =~ /[a-zA-Z0-9_]/
      end

      # Checks if a character is numeric
      #
      # @param char [String] the character to check
      # @return [Boolean] true if numeric
      def numeric_char?(char)
        char =~ /[0-9]/
      end

      # Parses a numeric literal
      #
      # @return [String] the numeric value
      def parse_numeric
        start_pos = @pos

        @pos += 1 while @pos < @input.length && numeric_char?(@input[@pos])

        @input[start_pos...@pos]
      end

      # Parses a string literal (single-quoted)
      #
      # @return [String] the string value (without quotes)
      def parse_string_literal
        consume("'")
        start_pos = @pos

        while @pos < @input.length && @input[@pos] != "'"
          # Handle escaped quotes
          @pos += 1 if @input[@pos] == "\\" && @pos + 1 < @input.length
          @pos += 1
        end

        value = @input[start_pos...@pos]
        consume("'")
        value
      end

      # Returns the current character without consuming it
      #
      # @return [String, nil] the current character or nil if at end
      def peek
        skip_whitespace
        @pos < @input.length ? @input[@pos] : nil
      end

      # Consumes an expected character
      #
      # @param expected [String] the expected character
      # @raise [ParseError] if the character doesn't match
      def consume(expected)
        skip_whitespace
        actual = @pos < @input.length ? @input[@pos] : "end of input"

        unless actual == expected
          raise ParseError.new("Expected '#{expected}', got '#{actual}'", position: @pos, input: @input)
        end

        @pos += 1
      end

      # Skips whitespace characters
      def skip_whitespace
        @pos += 1 while @pos < @input.length && @input[@pos] =~ /\s/
      end
    end
  end
end
