# frozen_string_literal: true

module OrpcRails
  # Declaration only; export validates the schema and existing Rails route.
  class Endpoint
    attr_reader :controller, :action, :key, :http_method, :path, :input, :output, :success_status

    def initialize(controller:, action:, key:, method:, path:, input:, output:, success_status:)
      @controller = controller
      @action = action.to_s.dup.freeze
      @key = key.to_s.dup.freeze
      @http_method = method.to_s.upcase.freeze
      @path = path.to_s.dup.freeze
      @input = input
      @output = output
      @success_status = success_status
      freeze
    end
  end
end
