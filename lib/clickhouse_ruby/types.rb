# frozen_string_literal: true

# Load base class first, then modules, then parser, then specific types, then registry last
require_relative "types/base"
require_relative "types/null_safe"
require_relative "types/string_parser"
require_relative "types/parser"
require_relative "types/integer"
require_relative "types/float"
require_relative "types/decimal"
require_relative "types/string"
require_relative "types/date_time"
require_relative "types/uuid"
require_relative "types/boolean"
require_relative "types/array"
require_relative "types/map"
require_relative "types/tuple"
require_relative "types/nullable"
require_relative "types/low_cardinality"
require_relative "types/enum"
require_relative "types/registry"

module ClickhouseRuby
  # Type system for mapping between ClickHouse and Ruby types
  #
  # Key features:
  # - AST-based type parser (handles nested types correctly)
  # - Bidirectional conversion (Ruby ↔ ClickHouse)
  # - Proper handling of complex types (Array, Map, Tuple, Nullable)
  #
  # @example Parse a complex type
  #   parser = ClickhouseRuby::Types::Parser.new
  #   ast = parser.parse('Array(Tuple(String, UInt64))')
  #   # => { type: 'Array', args: [{ type: 'Tuple', args: [...] }] }
  #
  # @example Convert values
  #   type = ClickhouseRuby::Types.lookup('UInt64')
  #   type.cast(42)          # => 42
  #   type.serialize(42)     # => "42"
  #   type.deserialize("42") # => 42
  #
  module Types
    class << self
      # Returns the global type registry
      #
      # @return [Registry] the type registry
      def registry
        @registry ||= Registry.new.tap(&:register_defaults)
      end

      # Looks up a type by its ClickHouse type string
      #
      # @param type_string [String] the ClickHouse type (e.g., 'Array(String)')
      # @return [Base] the type instance
      def lookup(type_string)
        registry.lookup(type_string)
      end

      # Parses a ClickHouse type string into an AST
      #
      # @param type_string [String] the ClickHouse type string
      # @return [Hash] the parsed AST
      def parse(type_string)
        Parser.new.parse(type_string)
      end

      # Resets the registry (useful for testing)
      def reset!
        @registry = nil
      end
    end
  end
end
