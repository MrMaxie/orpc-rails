# frozen_string_literal: true

require_relative "strict_json"
require_relative "schema"

module OrpcRails
  # Internal JSON-only v1 wire codec. It does not validate application schemas.
  class RpcCodec
    ERRORS = {
      "BAD_REQUEST" => [400, "Invalid RPC request"].freeze,
      "NOT_FOUND" => [404, "Procedure not found"].freeze,
      "METHOD_NOT_SUPPORTED" => [405, "Method not supported"].freeze,
      "UNSUPPORTED_MEDIA_TYPE" => [415, "Unsupported media type"].freeze,
      "PAYLOAD_TOO_LARGE" => [413, "Request body too large"].freeze,
      "INTERNAL_SERVER_ERROR" => [500, "Internal server error"].freeze
    }.freeze

    class Failure < StandardError
      attr_reader :code
      def initialize(code)
        @code = code
        super(ERRORS.fetch(code).last)
      end
    end

    attr_reader :max_body_bytes, :max_nesting

    def initialize(max_body_bytes: 1_048_576, max_nesting: 64)
      unless max_body_bytes.is_a?(Integer) && max_body_bytes >= 1024 &&
          max_nesting.is_a?(Integer) && max_nesting >= 3
        raise ArgumentError, "RPC limits require integer bytes >= 1024 and nesting >= 3"
      end
      @max_body_bytes = max_body_bytes
      @max_nesting = max_nesting
      freeze
    end

    def read(stream)
      body = +"".b
      while body.bytesize <= max_body_bytes
        chunk = stream.read(max_body_bytes + 1 - body.bytesize)
        break if chunk.nil? || chunk.empty?
        body << chunk
      end
      raise Failure.new("PAYLOAD_TOO_LARGE") if body.bytesize > max_body_bytes
      body
    end

    def decode(body)
      raise Failure.new("PAYLOAD_TOO_LARGE") if body.bytesize > max_body_bytes
      envelope = StrictJson.parse(body, max_nesting: max_nesting)
      unless envelope.is_a?(Hash) && envelope.key?("json") &&
          (envelope.keys - %w[json meta]).empty? &&
          (!envelope.key?("meta") || envelope["meta"] == [])
        raise Failure.new("BAD_REQUEST")
      end
      # Reuse the non-coercing profile traversal without constructing wire JSON.
      serialize(envelope, code: "BAD_REQUEST", emit: false)
      envelope.fetch("json")
    rescue StrictJson::Invalid
      raise Failure.new("BAD_REQUEST")
    end

    def encode(value)
      serialize({ "json" => value, "meta" => [] }, code: "INTERNAL_SERVER_ERROR")
    end

    def failure(code)
      status, message = ERRORS.fetch(code)
      [status, encode({ "defined" => false, "code" => code, "status" => status,
        "message" => message, "data" => {} })]
    end

    private

    # Iterative, incremental encoding also bounds cycles and avoids custom
    # to_json hooks. Only plain JSON containers/scalars cross the wire.
    def serialize(value, code:, emit: true)
      output = +""
      frames = [[:value, value, 0]]
      append = lambda do |text|
        if emit
          raise Failure.new(code) if output.bytesize + text.bytesize > max_body_bytes
          output << text
        end
      end
      until frames.empty?
        kind, item, depth, first = frames.pop
        if kind == :object || kind == :array
          begin
            member = item.next
          rescue StopIteration
            append.call(kind == :object ? "}" : "]")
            next
          end
          append.call(",") unless first
          frames << [kind, item, depth, false]
          if kind == :object
            key, member = member
            append.call(quote(key, code) + ":")
          end
          frames << [:value, member, depth]
          next
        end

        case item
        when Hash, Array
          raise Failure.new(code) unless item.instance_of?(Hash) || item.instance_of?(Array)
          depth += 1
          raise Failure.new(code) if depth > max_nesting
          object = item.instance_of?(Hash)
          append.call(object ? "{" : "[")
          frames << [object ? :object : :array, object ? item.each_pair : item.each, depth, true]
        when String
          append.call(quote(item, code))
        when Integer, Float
          valid = item.instance_of?(Integer) || (item.instance_of?(Float) && item.finite?)
          valid &&= item.between?(Schema::SAFE_INTEGER_MIN, Schema::SAFE_INTEGER_MAX) if valid && item == item.to_i
          raise Failure.new(code) unless valid
          append.call(JSON.generate(item))
        when true, false, nil
          append.call(JSON.generate(item))
        else
          raise Failure.new(code)
        end
      end
      output
    end

    def quote(value, code)
      unless value.instance_of?(String) && value.valid_encoding? &&
          (value.encoding == Encoding::UTF_8 || value.ascii_only?) && value.bytesize <= max_body_bytes
        raise Failure.new(code)
      end
      JSON.generate(String.new(value).force_encoding(Encoding::UTF_8))
    end
  end
end
