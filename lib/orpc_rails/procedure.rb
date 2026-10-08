# frozen_string_literal: true

require_relative "exporter"
require_relative "schema"

module OrpcRails
  class Error < StandardError
    attr_reader :code, :data
    def initialize(code, message:, data:)
      @code, @data = code, data
      super(message)
    end
  end

  class Procedure
    attr_reader :key, :input, :output, :errors, :handler

    def initialize(key, input:, output:, errors: {}, &handler)
      raise ArgumentError, "Procedure key must be a String" unless key.is_a?(String)
      Exporter.router_segments(key)
      raise ArgumentError, "Procedure requires a handler" unless handler
      [input, output].each { |node| validate_schema!(node) }
      raise ArgumentError, "Errors must be a Hash" unless errors.is_a?(Hash)
      @key = key.dup.freeze
      @input, @output = input, output
      @handler = handler.freeze
      @errors = errors.each_with_object({}) do |(code, definition), result|
        unless code.is_a?(String) && !code.strip.empty? &&
            !Schema::Node::UNSAFE_PROPERTY_KEYS.include?(code) && definition.is_a?(Hash) &&
            (definition.keys - [:status, :data]).empty? && definition[:status].is_a?(Integer) &&
            definition[:status].between?(400, 599)
          raise ArgumentError, "Invalid procedure error declaration"
        end
        validate_schema!(definition[:data])
        result[code.dup.freeze] = { status: definition[:status], data: definition[:data] }.freeze
      end.freeze
      freeze
    end

    private

    def validate_schema!(node)
      raise ArgumentError, "Procedure schemas require Schema nodes" unless node.is_a?(Schema::Node)
      node.to_zod # Reject root optional nodes before registration/export.
    end
  end
end
