# frozen_string_literal: true

require "json"
require "strscan"

module OrpcRails
  # Internal lexical prepass: ordinary JSON parsers can lose duplicate members.
  # An explicit frame stack bounds nesting without recursing on attacker input.
  class StrictJson
    class Invalid < StandardError; end
    STRING = /"(?:[^"\\\x00-\x1f]|\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4}))*"/.freeze
    NUMBER = /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.freeze
    PARSE_OPTIONS = (JSON::VERSION.split(".").first.to_i < 3 ? { create_additions: false } : {}).freeze

    def self.parse(source, max_nesting:)
      new(source, max_nesting).parse
    end

    def initialize(source, max_nesting)
      @source = source.dup.force_encoding(Encoding::UTF_8)
      raise Invalid unless @source.valid_encoding?
      @scanner = StringScanner.new(@source)
      @max_nesting = max_nesting
      @frames = [{ kind: :root, state: :value }]
    end

    def parse
      until @frames.empty?
        @scanner.skip(/[ \t\r\n]*/)
        frame = @frames.last
        case frame[:state]
        when :done
          raise Invalid unless @scanner.eos?
          @frames.pop
        when :key_first, :key
          if frame[:state] == :key_first && @scanner.scan(/\}/)
            @frames.pop
          else
            key = string!
            raise Invalid if frame[:keys].key?(key)
            frame[:keys][key] = true
            frame[:state] = :colon
          end
        when :colon
          raise Invalid unless @scanner.scan(/:/)
          frame[:state] = :value
        when :array_first
          if @scanner.scan(/\]/)
            @frames.pop
          else
            value!(frame)
          end
        when :value
          value!(frame)
        when :comma
          closer = frame[:kind] == :object ? /\}/ : /\]/
          if @scanner.scan(closer)
            @frames.pop
          elsif @scanner.scan(/,/)
            frame[:state] = frame[:kind] == :object ? :key : :value
          else
            raise Invalid
          end
        end
      end
      JSON.parse(@source, **PARSE_OPTIONS, max_nesting: @max_nesting, allow_nan: false)
    rescue JSON::ParserError, ArgumentError
      raise Invalid
    end

    private

    def value!(frame)
      frame[:state] = frame[:kind] == :root ? :done : :comma
      if @scanner.scan(/\{/)
        container!(:object, :key_first)
      elsif @scanner.scan(/\[/)
        container!(:array, :array_first)
      elsif @scanner.peek(1) == '"'
        string!
      elsif !@scanner.scan(/true|false|null/) && !@scanner.scan(NUMBER)
        raise Invalid
      end
    end

    def container!(kind, state)
      # Root frame is not a container; its stack position is the wire depth.
      raise Invalid if @frames.length > @max_nesting
      @frames << { kind: kind, state: state, keys: {} }
    end

    def string!
      token = @scanner.scan(STRING)
      raise Invalid unless token
      value = JSON.parse(token, **PARSE_OPTIONS)
      raise Invalid unless value.valid_encoding?
      value
    end
  end
end
