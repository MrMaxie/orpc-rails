# frozen_string_literal: true

require_relative "schema"

module OrpcRails
  # Pure IR conformance, separate from additional RPC wire/resource limits.
  module Validator
    def self.valid?(schema, value)
      pending = [[schema, value]]
      until pending.empty?
        node, item = pending.pop
        options = node.options
        case node.kind
        when :nullable
          pending << [node.children, item] unless item.nil?
        when :object
          return false unless item.instance_of?(Hash) && item.keys.all? { |key| key.instance_of?(String) }
          return false unless (item.keys - node.children.keys).empty?
          node.children.each do |key, child|
            if child.kind == :optional
              pending << [child.children, item[key]] if item.key?(key)
            else
              return false unless item.key?(key)
              pending << [child, item[key]]
            end
          end
        when :array
          return false unless item.instance_of?(Array) && within?(item.length, options[:min_length], options[:max_length])
          item.each { |child| pending << [node.children, child] }
        when :string
          return false unless string?(item) && within?(item.length, options[:min_length], options[:max_length])
        when :enum
          return false unless string?(item) && options[:values].include?(item)
        when :number, :integer
          return false unless number?(item) && within?(item, options[:min], options[:max])
          return false if node.kind == :integer && item != item.to_i
        when :boolean
          return false unless item.instance_of?(TrueClass) || item.instance_of?(FalseClass)
        when :literal
          expected = options[:value]
          same_type = if expected.is_a?(Numeric)
            number?(item)
          elsif expected.is_a?(String)
            string?(item)
          else
            item.class == expected.class
          end
          return false unless same_type && item == expected
        else
          return false
        end
      end
      true
    end

    def self.within?(value, min, max)
      (min.nil? || value >= min) && (max.nil? || value <= max)
    end
    private_class_method :within?

    def self.number?(value)
      value.instance_of?(Integer) || (value.instance_of?(Float) && value.finite?)
    end
    private_class_method :number?

    def self.string?(value)
      value.instance_of?(String) && value.valid_encoding? &&
        (value.encoding == Encoding::UTF_8 || value.ascii_only?)
    end
    private_class_method :string?
  end
end
