# frozen_string_literal: true

require_relative "registry"
require_relative "endpoint"

module OrpcRails
  def self.registry
    @registry ||= Registry.new
  end

  # No callbacks or rendering hooks: this is export-only metadata.
  module Controller
    def self.included(controller)
      controller.extend(ClassMethods)
    end

    module ClassMethods
      def orpc_contract(action, **options)
        endpoint = Endpoint.new(controller: self, action: action, **options)
        @orpc_contracts = (orpc_contracts + [endpoint]).freeze
        OrpcRails.registry.register(self)
        endpoint
      end

      def orpc_contracts
        @orpc_contracts || [].freeze
      end
    end
  end
end
