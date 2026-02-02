# frozen_string_literal: true

module ClickhouseRuby
  module Types
    # Registry for ClickHouse type mappings
    #
    # Manages the mapping between ClickHouse type strings and Ruby type classes.
    # Supports both simple types (String, UInt64) and parameterized types
    # (Array, Map, Nullable).
    #
    # @example Register a custom type
    #   registry = Registry.new
    #   registry.register('MyType', MyTypeClass)
    #
    # @example Look up a type
    #   type = registry.lookup('Array(String)')
    #
    class Registry
      # Types that wrap other types (parameterized types)
      WRAPPER_TYPES = %w[Array Nullable LowCardinality].freeze

      # Types that take multiple type arguments
      MULTI_ARG_TYPES = %w[Map Tuple].freeze

      # DateTime types that take precision/timezone parameters
      DATETIME_TYPES = %w[DateTime DateTime64].freeze

      def initialize
        @types = {}
        @cache = {}
      end

      # Registers a type class for a type name
      #
      # @param name [String] the type name (e.g., 'String', 'UInt64')
      # @param type_class [Class] the type class
      def register(name, type_class)
        @types[name] = type_class
        @cache.clear # Invalidate cache when types change
      end

      # Looks up a type by its ClickHouse type string
      #
      # @param type_string [String] the full type string (e.g., 'Array(String)')
      # @return [Base] the type instance
      def lookup(type_string)
        # Check cache first
        return @cache[type_string] if @cache.key?(type_string)

        # Parse the type string
        ast = Parser.new.parse(type_string)

        # Build the type instance
        type = build_type(ast)

        # Cache for future lookups
        @cache[type_string] = type

        type
      end

      # Registers all default ClickHouse types
      def register_defaults
        # Integer types
        register("Int8", Integer)
        register("Int16", Integer)
        register("Int32", Integer)
        register("Int64", Integer)
        register("Int128", Integer)
        register("Int256", Integer)
        register("UInt8", Integer)
        register("UInt16", Integer)
        register("UInt32", Integer)
        register("UInt64", Integer)
        register("UInt128", Integer)
        register("UInt256", Integer)

        # Float types
        register("Float32", Float)
        register("Float64", Float)

        # Decimal types
        register("Decimal", Decimal)
        register("Decimal32", Decimal)
        register("Decimal64", Decimal)
        register("Decimal128", Decimal)
        register("Decimal256", Decimal)

        # String types
        register("String", String)
        register("FixedString", String)

        # Date/Time types
        register("Date", DateTime)
        register("Date32", DateTime)
        register("DateTime", DateTime)
        register("DateTime64", DateTime)

        # Other basic types
        register("UUID", UUID)
        register("Bool", Boolean)

        # Complex/wrapper types
        register("Array", Array)
        register("Map", Map)
        register("Tuple", Tuple)
        register("Nullable", Nullable)
        register("LowCardinality", LowCardinality)

        # Enum types
        register("Enum", Enum)
        register("Enum8", Enum)
        register("Enum16", Enum)
      end

      private

      # Builds a type instance from a parsed AST
      #
      # @param ast [Hash] the parsed type AST
      # @return [Base] the type instance
      def build_type(ast)
        type_name = ast[:type]
        args = ast[:args]

        type_class = @types[type_name]

        unless type_class
          # For unknown types, return a generic type that passes through values
          return Base.new(type_name)
        end

        if args && !args.empty?
          if DATETIME_TYPES.include?(type_name)
            # DateTime types: DateTime64(3) or DateTime64(3, 'UTC')
            precision = args[0] ? args[0][:type].to_i : nil
            timezone = args[1] ? args[1][:type] : nil
            type_class.new(type_name, precision: precision, timezone: timezone)
          elsif WRAPPER_TYPES.include?(type_name)
            # Single-argument wrapper (Array, Nullable, LowCardinality)
            arg_types = args.map { |arg| build_type(arg) }
            type_class.new(type_name, element_type: arg_types.first)
          elsif MULTI_ARG_TYPES.include?(type_name)
            # Multi-argument type (Map, Tuple)
            arg_types = args.map { |arg| build_type(arg) }
            type_class.new(type_name, arg_types: arg_types)
          else
            # Other parameterized types - pass raw args
            arg_types = args.map { |arg| build_type(arg) }
            type_class.new(type_name, arg_types: arg_types)
          end
        else
          # Simple type
          type_class.new(type_name)
        end
      end
    end
  end
end
