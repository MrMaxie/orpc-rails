# frozen_string_literal: true

require_relative "exporter"
require_relative "procedures"

module OrpcRails
  # Separate procedure surface; shares atomic writes/checks with HTTP exports.
  class RpcExporter < Exporter
    def initialize(controller:)
      @controller_name = controller
    end

    def generate
      controller = OrpcRails.procedure_registry.controller(@controller_name)
      unless controller && controller.respond_to?(:orpc_procedures) && !controller.orpc_procedures.empty?
        raise ArgumentError, "Select a registered procedure controller"
      end
      tree = {}
      schema_lines = []
      controller.orpc_procedures.sort_by(&:key).each do |procedure|
        key = quote(procedure.key)
        errors = procedure.errors.sort.map do |code, definition|
          "#{quote(code)}: { status: #{definition[:status]}, data: #{definition[:data].to_zod} }"
        end.join(", ")
        insert(tree, procedure.key, "oc.input(schemas[#{key}].input).output(schemas[#{key}].output).errors({#{errors}})")
        schema_lines << "  #{key}: { input: #{procedure.input.to_zod}, output: #{procedure.output.to_zod} }"
      end
      [
        'import * as z from "zod"', 'import { oc } from "@orpc/contract"', "",
        "export const schemas = {", schema_lines.join(",\n"), "} as const", "",
        "export const contract = #{render_tree(tree)}", "", "export type Contract = typeof contract", ""
      ].join("\n").encode(Encoding::UTF_8)
    end

    def check(path)
      unless File.file?(path) && File.binread(path) == generate
        raise ArgumentError, "Contract drift: regenerate #{path} with orpc:export_rpc"
      end
      true
    end
  end
end
