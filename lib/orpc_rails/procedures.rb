# frozen_string_literal: true

require "uri"
require_relative "registry"
require_relative "procedure"
require_relative "rpc_codec"
require_relative "validator"

module OrpcRails
  def self.procedure_registry
    @procedure_registry ||= Registry.new
  end

  # Explicit opt-in controller action. No routes, callbacks or security changes.
  module Procedures
    def self.included(controller)
      controller.extend(ClassMethods)
    end

    module ClassMethods
      def orpc_procedure(key, **options, &handler)
        raise ArgumentError, "Procedure controllers must have a constant name" unless name
        declaration = Procedure.new(key, **options, &handler)
        if orpc_procedures.any? { |other| other.key == key || other.key.start_with?(key + ".") || key.start_with?(other.key + ".") }
          raise ArgumentError, "Duplicate or prefix-colliding procedure key"
        end
        @orpc_procedures = (orpc_procedures + [declaration]).freeze
        OrpcRails.procedure_registry.register(self)
        declaration
      end

      def orpc_procedures
        @orpc_procedures || [].freeze
      end

      def orpc_limits(**limits)
        @orpc_codec = RpcCodec.new(**limits)
      end

      def orpc_codec
        @orpc_codec ||= RpcCodec.new
      end
    end

    def orpc_dispatch
      codec = self.class.orpc_codec
      raise RpcCodec::Failure.new("METHOD_NOT_SUPPORTED") unless request.post?
      raise RpcCodec::Failure.new("UNSUPPORTED_MEDIA_TYPE") unless request.media_type == "application/json"
      procedure = selected_procedure
      raise RpcCodec::Failure.new("NOT_FOUND") unless procedure
      cached = request.get_header("RAW_POST_DATA")
      input = codec.decode(cached || codec.read(request.body))
      raise RpcCodec::Failure.new("BAD_REQUEST") unless Validator.valid?(procedure.input, input)
      begin
        context = orpc_context
        output = instance_exec(input: input, context: context, &procedure.handler)
        raise RpcCodec::Failure.new("INTERNAL_SERVER_ERROR") unless Validator.valid?(procedure.output, output)
        body = codec.encode(output)
        status = 200
      rescue OrpcRails::Error => error
        definition = procedure.errors[error.code]
        unless definition && Validator.valid?(definition[:data], error.data) && error.message.is_a?(String)
          raise RpcCodec::Failure.new("INTERNAL_SERVER_ERROR")
        end
        status = definition[:status]
        body = codec.encode({ "defined" => true, "code" => error.code, "status" => status,
          "message" => error.message, "data" => error.data })
      end
      render body: body, content_type: "application/json", status: status
    rescue RpcCodec::Failure => error
      render_rpc_failure(codec, error.code)
    rescue StandardError
      render_rpc_failure(codec, "INTERNAL_SERVER_ERROR")
    end

    private

    def orpc_context
      {}
    end

    def selected_procedure
      # Rails route recognition decodes segments; inspect the original path too.
      raw_path = request.get_header("REQUEST_URI") || request.get_header("ORIGINAL_FULLPATH") || request.path
      raw_path = URI.parse(raw_path).path if raw_path.start_with?("http://", "https://")
      raw_path = raw_path.split("?", 2).first
      return nil if raw_path.end_with?("/") || raw_path.include?("%") || raw_path.include?("//") || raw_path.match?(%r{/(?:\.|\.\.)(?:/|\z)})
      path = request.path_parameters[:orpc_path].to_s
      segments = path.split("/", -1)
      return nil if segments.empty? || segments.any? { |part| !part.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/) }
      self.class.orpc_procedures.find { |procedure| procedure.key == segments.join(".") }
    rescue URI::InvalidURIError
      nil
    end

    def render_rpc_failure(codec, code)
      response.set_header("Allow", "POST") if code == "METHOD_NOT_SUPPORTED"
      status, body = codec.failure(code)
      render body: body, content_type: "application/json", status: status
    end
  end
end
