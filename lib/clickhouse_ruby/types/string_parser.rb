# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Shared utilities for parsing ClickHouse string representations
    # of complex types (arrays, tuples, maps)
    #
    # These methods handle the common patterns of parsing nested structures
    # with proper handling of quotes, escape characters, and bracket depth.
    #
    module StringParser
      module_function

      # Parses a comma-separated list of elements, respecting nested structures and quotes
      #
      # @param str [String] the string to parse
      # @param open_brackets [Array<String>] characters that increase nesting depth
      # @param close_brackets [Array<String>] characters that decrease nesting depth
      # @return [Array<String>] parsed elements
      #
      # @example
      #   StringParser.parse_delimited("a, b, c")
      #   # => ["a", "b", "c"]
      #
      #   StringParser.parse_delimited("'hello', [1, 2], 'world'")
      #   # => ["'hello'", "[1, 2]", "'world'"]
      #
      def parse_delimited(str, open_brackets: ["[", "(", "{"], close_brackets: ["]", ")", "}"])
        elements = []
        current = +""
        depth = 0
        in_string = false
        escape_next = false

        str.each_char do |char|
          if escape_next
            current << char
            escape_next = false
            next
          end

          case char
          when "\\"
            escape_next = true
            current << char
          when "'"
            in_string = !in_string
            current << char
          when *open_brackets
            depth += 1 unless in_string
            current << char
          when *close_brackets
            depth -= 1 unless in_string
            current << char
          when ","
            if depth.zero? && !in_string
              elements << current.strip
              current = +""
            else
              current << char
            end
          else
            current << char
          end
        end

        elements << current.strip unless current.strip.empty?
        elements
      end

      # Removes surrounding single quotes and unescapes content
      #
      # @param str [String] potentially quoted string
      # @return [String] unquoted string with escapes processed
      #
      # @example
      #   StringParser.unquote("'hello'")
      #   # => "hello"
      #
      #   StringParser.unquote("'it\\'s'")
      #   # => "it's"
      #
      #   StringParser.unquote("123")
      #   # => "123"
      #
      def unquote(str)
        str = str.strip
        if str.start_with?("'") && str.end_with?("'") && str.length >= 2
          str[1...-1].gsub("\\'", "'")
        else
          str
        end
      end

      # Validates and extracts content from a bracketed string
      #
      # @param str [String] bracketed string like "[...]" or "(...)"
      # @param open_bracket [String] expected opening bracket
      # @param close_bracket [String] expected closing bracket
      # @return [String] inner content (may be empty)
      # @raise [ArgumentError] if format is invalid
      #
      # @example
      #   StringParser.extract_bracketed("[1, 2, 3]", "[", "]")
      #   # => "1, 2, 3"
      #
      def extract_bracketed(str, open_bracket, close_bracket)
        str = str.strip
        unless str.start_with?(open_bracket) && str.end_with?(close_bracket) && str.length >= 2
          raise ArgumentError, "Expected #{open_bracket}...#{close_bracket} format, got: '#{str}'"
        end

        str[1...-1]
      end

      # Parses elements and unquotes them in one step
      #
      # @param str [String] the string to parse
      # @param open_brackets [Array<String>] characters that increase nesting depth
      # @param close_brackets [Array<String>] characters that decrease nesting depth
      # @return [Array<String>] parsed and unquoted elements
      #
      def parse_and_unquote(str, open_brackets: ["[", "(", "{"], close_brackets: ["]", ")", "}"])
        parse_delimited(str, open_brackets: open_brackets, close_brackets: close_brackets).map do |el|
          # Only unquote simple quoted strings, preserve nested structures
          if el.start_with?("'") && el.end_with?("'") && !el.include?("[") && !el.include?("(") && !el.include?("{")
            unquote(el)
          else
            el
          end
        end
      end
    end
  end
end
