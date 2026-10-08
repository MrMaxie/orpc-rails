# frozen_string_literal: true

require "json"
require "tempfile"
require_relative "controller"
require_relative "routes"
require_relative "http_mapping"

module OrpcRails
  class Exporter
    RESERVED = %w[then bind call apply valueOf toString toJSON __proto__ constructor prototype].freeze

    def initialize(routes:, endpoints: nil)
      @routes = Routes.new(routes)
      @endpoints = endpoints
    end

    def generate
      endpoints = (@endpoints || OrpcRails.registry.endpoints).sort_by(&:key)
      tree = {}
      schema_lines = []
      endpoints.each do |endpoint|
        mapping = HttpMapping.new(endpoint)
        mapping.validate!
        @routes.validate!(endpoint)
        segments = endpoint.key.split(".", -1)
        unless segments.all? { |key| key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/) && !RESERVED.include?(key) }
          raise ArgumentError, "#{endpoint.key}: invalid or reserved router key"
        end
        branch = tree
        segments.each_with_index do |key, index|
          if index == segments.size - 1
            raise ArgumentError, "#{endpoint.key}: duplicate or prefix-colliding router key" if branch.key?(key)
            branch[key] = "oc.route(#{JSON.generate(mapping.route)}).input(schemas[#{quote(endpoint.key)}].input).output(schemas[#{quote(endpoint.key)}].output)"
          else
            branch[key] ||= {}
            raise ArgumentError, "#{endpoint.key}: prefix-colliding router key" unless branch[key].is_a?(Hash)
            branch = branch[key]
          end
        end
        schema_lines << "  #{quote(endpoint.key)}: { input: #{endpoint.input.to_zod}, output: #{endpoint.output.to_zod} }"
      end
      [
        'import * as z from "zod"',
        'import { oc } from "@orpc/contract"', "",
        "export const schemas = {", schema_lines.join(",\n"), "} as const", "",
        "export const contract = #{render_tree(tree)}", "",
        "export type Contract = typeof contract", ""
      ].join("\n").encode(Encoding::UTF_8)
    end

    def write(path)
      source = generate
      destination = File.expand_path(path)
      Tempfile.create([".orpc-contract-", ".ts"], File.dirname(destination)) do |file|
        file.binmode
        file.write(source)
        file.flush
        file.fsync
        file.close
        File.rename(file.path, destination)
      end
      destination
    end

    def check(path)
      source = generate
      unless File.file?(path) && File.binread(path) == source
        raise ArgumentError, "Contract drift: regenerate #{path} with orpc:export"
      end
      true
    end

    private

    def quote(value)
      JSON.generate(value, ascii_only: true)
    end

    def render_tree(tree)
      "{#{tree.keys.sort.map { |key| "#{quote(key)}: #{tree[key].is_a?(Hash) ? render_tree(tree[key]) : tree[key]}" }.join(', ')}}"
    end
  end
end
