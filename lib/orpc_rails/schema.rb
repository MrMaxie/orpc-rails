# frozen_string_literal: true

require "json"

module OrpcRails
  # Bounded, immutable schema representation shared by export and later
  # procedure validation. Builds safe Zod v4 expressions only; it performs
  # no runtime payload validation.
  module Schema
    SAFE_INTEGER_MAX = 9_007_199_254_740_991
    SAFE_INTEGER_MIN = -9_007_199_254_740_991

    # Immutable schema node. kind is a Symbol, options a frozen Hash, and
    # children is a frozen Hash with String keys (object nodes), an inner
    # Node (array/optional/nullable nodes) or nil (primitives).
    class Node
      KINDS = %i[string number integer boolean literal enum array object
                 optional nullable].freeze
      PRIMITIVE_KINDS = %i[string number integer boolean literal enum].freeze
      LENGTH_KINDS = %i[string array].freeze
      BOUND_KINDS = %i[number integer].freeze
      WRAPPER_KINDS = %i[array optional nullable].freeze

      OPTION_KEYS = {
        string: %i[min_length max_length],
        number: %i[min max],
        integer: %i[min max],
        boolean: [].freeze,
        literal: %i[value],
        enum: %i[values],
        array: %i[min_length max_length],
        object: [].freeze,
        optional: [].freeze,
        nullable: [].freeze
      }.freeze

      UNSAFE_PROPERTY_KEYS = %w[__proto__ constructor prototype].freeze

      attr_reader :kind, :options, :children

      def initialize(kind, options = {}, children = nil)
        unless KINDS.include?(kind)
          raise ArgumentError, "unsupported node kind: #{kind.inspect}"
        end

        @kind = kind
        @options = normalize_options(kind, options).freeze
        @children = normalize_children(kind, children)
        freeze
      end

      # Returns a safe Zod v4 expression string. Optional nodes are only
      # valid as object properties, so rendering one directly is rejected.
      def to_zod
        case kind
        when :string
          bounded("z.string()", options[:min_length], options[:max_length])
        when :number
          bounded("z.number()", options[:min], options[:max])
        when :integer
          expr = +"z.int()"
          expr << ".min(#{json_quote(options[:min])})" unless options[:min] == SAFE_INTEGER_MIN
          expr << ".max(#{json_quote(options[:max])})" unless options[:max] == SAFE_INTEGER_MAX
          expr
        when :boolean
          "z.boolean()"
        when :literal
          "z.literal(#{json_quote(options[:value])})"
        when :enum
          "z.enum([#{options[:values].map { |value| json_quote(value) }.join(', ')}])"
        when :array
          bounded("z.array(#{children.to_zod})", options[:min_length], options[:max_length])
        when :object
          props = children.map { |key, node| "#{json_quote(key)}: #{property_zod(node)}" }
          "z.strictObject({#{props.join(', ')}})"
        when :optional
          raise ArgumentError,
                "optional nodes are only valid as object properties and cannot be rendered directly"
        when :nullable
          "#{children.to_zod}.nullable()"
        end
      end

      def optional
        Node.new(:optional, {}, self)
      end

      def nullable
        Node.new(:nullable, {}, self)
      end

      private

      def normalize_options(kind, options)
        raise ArgumentError, "options must be a Hash" unless options.is_a?(Hash)

        allowed = OPTION_KEYS.fetch(kind)
        options.each_key do |key|
          unless allowed.include?(key)
            raise ArgumentError, "unsupported option #{key.inspect} for #{kind} node"
          end
        end

        values = {}
        allowed.each { |key| values[key] = options.fetch(key, nil) }
        case kind
        when :string, :array
          values[:min_length] = normalize_length(values[:min_length], :min_length)
          values[:max_length] = normalize_length(values[:max_length], :max_length)
          check_order(values[:min_length], values[:max_length])
        when :number
          values[:min] = normalize_finite_number(values[:min], :min)
          values[:max] = normalize_finite_number(values[:max], :max)
          check_order(values[:min], values[:max])
        when :integer
          values[:min] = normalize_integer_bound(values[:min], :min, SAFE_INTEGER_MIN)
          values[:max] = normalize_integer_bound(values[:max], :max, SAFE_INTEGER_MAX)
          check_order(values[:min], values[:max])
        when :literal
          values[:value] = normalize_literal(values[:value])
        when :enum
          values[:values] = normalize_enum(values[:values])
        end
        values
      end

      def normalize_children(kind, children)
        if PRIMITIVE_KINDS.include?(kind)
          unless children.nil?
            raise ArgumentError, "#{kind} nodes must not have children"
          end
          return nil
        end

        if kind == :object
          return normalize_object(children)
        end

        unless children.is_a?(Node)
          raise ArgumentError, "#{kind} nodes require an inner Node"
        end
        if WRAPPER_KINDS.include?(kind) && children.kind == :optional
          raise ArgumentError,
                kind == :array ? "array elements must not be optional" :
                "#{kind} nodes must not wrap optional nodes"
        end
        children
      end

      def normalize_object(children)
        raise ArgumentError, "object nodes require a property Hash" unless children.is_a?(Hash)

        normalized = {}
        children.each do |key, node|
          name = copy_key(key)
          if UNSAFE_PROPERTY_KEYS.include?(name)
            raise ArgumentError, "unsafe object property key: #{name.inspect}"
          end
          unless node.is_a?(Node)
            raise ArgumentError, "unsupported property node for #{name.inspect}: #{node.inspect}"
          end
          if normalized.key?(name)
            raise ArgumentError, "duplicate object property key: #{name.inspect}"
          end
          normalized[name] = node
        end
        normalized.keys.sort.each_with_object({}) { |key, sorted| sorted[key] = normalized[key] }.freeze
      end

      def copy_key(key)
        raise ArgumentError, "object property keys must be Strings or Symbols" unless key.is_a?(String) || key.is_a?(Symbol)
        key.to_s.dup.freeze
      end

      def normalize_length(value, name)
        return nil if value.nil?
        unless value.is_a?(Integer) && value.between?(0, SAFE_INTEGER_MAX)
          raise ArgumentError, "#{name} must be a non-negative safe Integer or nil"
        end
        value
      end

      def normalize_finite_number(value, name)
        return nil if value.nil?
        unless (value.is_a?(Integer) && value.between?(SAFE_INTEGER_MIN, SAFE_INTEGER_MAX)) ||
            (value.is_a?(Float) && value.finite?)
          raise ArgumentError, "#{name} must be a finite Float or safe Integer or nil"
        end
        value
      end

      def normalize_integer_bound(value, name, default)
        value = default if value.nil?
        unless value.is_a?(Integer) && value.between?(SAFE_INTEGER_MIN, SAFE_INTEGER_MAX)
          raise ArgumentError,
                "#{name} must be an Integer within -(2^53 - 1)..(2^53 - 1)"
        end
        value
      end

      def check_order(min, max)
        return if min.nil? || max.nil? || min <= max
        raise ArgumentError, "minimum bound #{min.inspect} exceeds maximum bound #{max.inspect}"
      end

      def normalize_literal(value)
        case value
        when String
          value.dup.freeze
        when Integer
          unless value.between?(SAFE_INTEGER_MIN, SAFE_INTEGER_MAX)
            raise ArgumentError, "literal integers must stay within -(2^53 - 1)..(2^53 - 1)"
          end
          value
        when Float
          raise ArgumentError, "literal numbers must be finite" unless value.finite?
          value
        when true, false, nil
          value
        else
          raise ArgumentError, "unsupported literal value: #{value.inspect}"
        end
      end

      def normalize_enum(values)
        unless values.is_a?(Array) && !values.empty?
          raise ArgumentError, "enum requires at least one value"
        end
        values.each do |value|
          raise ArgumentError, "enum values must be Strings" unless value.is_a?(String)
        end
        if values.map(&:dup).uniq.size != values.size
          raise ArgumentError, "enum values must be unique"
        end
        values.map { |value| value.dup.freeze }.freeze
      end

      def bounded(base, min, max)
        expr = +base
        expr << ".min(#{json_quote(min)})" unless min.nil?
        expr << ".max(#{json_quote(max)})" unless max.nil?
        expr
      end

      def property_zod(node)
        node.kind == :optional ? "#{node.children.to_zod}.optional()" : node.to_zod
      end

      def json_quote(value)
        JSON.generate(value, { ascii_only: true })
      end
    end

    class << self
      def string(min_length: nil, max_length: nil)
        Node.new(:string, { min_length: min_length, max_length: max_length }, nil)
      end

      def number(min: nil, max: nil)
        Node.new(:number, { min: min, max: max }, nil)
      end

      def integer(min: SAFE_INTEGER_MIN, max: SAFE_INTEGER_MAX)
        Node.new(:integer, { min: min, max: max }, nil)
      end

      def boolean
        Node.new(:boolean, {}, nil)
      end

      def literal(value)
        Node.new(:literal, { value: value }, nil)
      end

      def enum(*values)
        Node.new(:enum, { values: values }, nil)
      end

      def array(inner, min_length: nil, max_length: nil)
        Node.new(:array, { min_length: min_length, max_length: max_length }, inner)
      end

      def object(**fields)
        Node.new(:object, {}, fields)
      end
    end
  end
end
