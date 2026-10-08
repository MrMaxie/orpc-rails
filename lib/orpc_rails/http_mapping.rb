# frozen_string_literal: true

require_relative "schema"

module OrpcRails
  class HttpMapping
    METHODS = %w[GET POST PUT PATCH DELETE].freeze
    LOCATIONS = %w[params query headers body].freeze

    def initialize(endpoint)
      @endpoint = endpoint
    end

    def validate!
      fail_at("method", "unsupported method") unless METHODS.include?(@endpoint.http_method)
      fail_at("success_status", "only 200 and 201 are supported") unless [200, 201].include?(@endpoint.success_status)
      unless @endpoint.path.match?(%r{\A/(?:[A-Za-z0-9_-]+|:[A-Za-z_][A-Za-z0-9_]*)(?:/(?:[A-Za-z0-9_-]+|:[A-Za-z_][A-Za-z0-9_]*))*\z}) || @endpoint.path == "/"
        fail_at("path", "only literal paths and required :segments are supported")
      end
      input = @endpoint.input
      fail_at("input", "must be an object schema") unless input.is_a?(Schema::Node) && input.kind == :object
      unknown = input.children.keys - LOCATIONS
      fail_at("input.#{unknown.first}", "unsupported input location") unless unknown.empty?
      segments = @endpoint.path.scan(/:([A-Za-z_][A-Za-z0-9_]*)/).flatten
      fail_at("path", "duplicate path parameters") unless segments.uniq == segments
      params = input.children["params"]
      if params
        object!(params, "input.params")
        fail_at("input.params", "must match path parameters exactly") unless params.children.keys.sort == segments.sort
        strings!(params, "input.params", optional: false)
      elsif !segments.empty?
        fail_at("input.params", "missing path parameters")
      end
      %w[query headers].each do |location|
        next unless (node = input.children[location])
        node = node.children if node.kind == :optional
        object!(node, "input.#{location}")
        strings!(node, "input.#{location}", optional: true)
        if location == "headers" && node.children.keys.any? { |key| !key.match?(/\A[a-z0-9!#$%&'*+.^_`|~-]+\z/) }
          fail_at("input.headers", "header names must be lowercase HTTP tokens")
        end
      end
      if input.children.key?("body") && @endpoint.http_method == "GET"
        fail_at("input.body", "GET bodies are not supported")
      end
      input.to_zod
      unless @endpoint.output.is_a?(Schema::Node)
        fail_at("output", "unsupported schema")
      end
      begin
        @endpoint.output.to_zod
      rescue ArgumentError => error
        fail_at("output", error.message)
      end
      true
    end

    def route
      { method: @endpoint.http_method, path: @endpoint.path.gsub(/:([A-Za-z_][A-Za-z0-9_]*)/, '{\1}'),
        inputStructure: "detailed", successStatus: @endpoint.success_status }
    end

    private

    def object!(node, location)
      fail_at(location, "must be an object") unless node.kind == :object
    end

    def strings!(node, location, optional:)
      node.children.each do |key, leaf|
        leaf = leaf.children if optional && leaf.kind == :optional
        fail_at("#{location}.#{key}", "must be a wire string") unless leaf.kind == :string
      end
    end

    def fail_at(location, message)
      raise ArgumentError, "#{@endpoint.key} #{location}: #{message}"
    end
  end
end
