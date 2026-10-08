# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "../lib/orpc_rails/rpc_codec"

class RpcCodecTest < Minitest::Test
  def setup
    @codec = OrpcRails::RpcCodec.new
  end

  def bad(source)
    error = assert_raises(OrpcRails::RpcCodec::Failure) { @codec.decode(source) }
    assert_equal "BAD_REQUEST", error.code
    refute_includes error.message, source unless source.empty?
  end

  def test_supported_envelopes_and_unicode
    [nil, true, false, 0, -1.5, "😀", [], {}].each do |value|
      [ { "json" => value }, { "json" => value, "meta" => [] } ].each do |envelope|
        actual = @codec.decode(JSON.generate(envelope))
        value.nil? ? assert_nil(actual) : assert_equal(value, actual)
      end
    end
    assert_equal({ "😀" => "😀" }, @codec.decode('{"json":{"\\uD83D\\uDE00":"\\uD83D\\uDE00"}}'))
    assert_equal({ "a" => 1 }, @codec.decode(" \t\r\n{\"json\": {\"a\":1}} \n"))
  end

  def test_duplicate_keys_at_every_depth_and_after_escape_decoding
    ['{"json":1,"json":2}', '{"json":{"a":1,"a":2}}',
      '{"json":[{"a":1,"\\u0061":2}]}', '{"json":{"😀":1,"\\uD83D\\uDE00":2}}',
      '{"json":null,"meta":[],"meta":[]}'].each { |source| bad(source) }
    assert_equal [{ "a" => 1 }, { "a" => 2 }], @codec.decode('{"json":[{"a":1},{"a":2}]}')
  end

  def test_strict_json_grammar
    ['', '{}', 'null', '[]', '{"json":', '{"json":0} true', '{"json":01}',
      '{"json":+1}', '{"json":.1}', '{"json":1.}', '{"json":1e}', '{"json":NaN}',
      '{"json":Infinity}', '{"json":[1,]}', '{"json":{"a":1,}}', '{"json":/*x*/1}',
      '{"json":"\\x61"}', '{"json":"\\uGGGG"}', "{\"json\":\"a\nb\"}",
      '{"json":true false}', '{"json":{a:1}}', '{"json":1,}', '{"json":1 "x":2}',
      '{"json":1,"meta":{}}', '{"json":1,"meta":[[1]]}', '{"json":1,"maps":{}}',
      '{"json":1,"extra":null}'].each { |source| bad(source) }
  end

  def test_raw_and_escaped_invalid_unicode
    ["{\"json\":\"\xFF\"}".b, '{"json":"\\uD800"}', '{"json":"\\uDC00"}',
      '{"json":{"\\uDC00":1}}', '{"json":"\\uD800x"}'].each { |source| bad(source) }
  end

  def test_finite_safe_numeric_wire_policy
    %w[9007199254740992 -9007199254740992 9007199254740992.0 9.007199254740992e15 1e400].each do |value|
      bad('{"json":' + value + '}')
    end
    assert_equal 9_007_199_254_740_991, @codec.decode('{"json":9007199254740991}')
    assert_equal 0.125, @codec.decode('{"json":1.25e-1}')
  end

  def test_wire_depth_includes_outer_object
    assert @codec.decode('{"json":' + '[' * 63 + '0' + ']' * 63 + '}')
    bad('{"json":' + '[' * 64 + '0' + ']' * 64 + '}')
    # Even attacker-controlled depth far beyond Ruby's call stack is rejected.
    bad('{"json":' + '[' * 10_000 + '0' + ']' * 10_000 + '}')
  end

  def test_byte_boundary_and_bounded_stream_read
    codec = OrpcRails::RpcCodec.new(max_body_bytes: 1024, max_nesting: 3)
    exact = '{"json":"' + 'x' * 1013 + '"}'
    assert_equal 1024, exact.bytesize
    assert_equal 'x' * 1013, codec.decode(exact)
    error = assert_raises(OrpcRails::RpcCodec::Failure) { codec.decode(exact + ' ') }
    assert_equal "PAYLOAD_TOO_LARGE", error.code
    stream = StringIO.new('x' * 10_000)
    assert_raises(OrpcRails::RpcCodec::Failure) { codec.read(stream) }
    assert_equal 1025, stream.pos
    assert_equal exact, codec.read(StringIO.new(exact))
  end

  def test_limit_configuration
    [{ max_body_bytes: 1023 }, { max_body_bytes: 1024.0 }, { max_nesting: 2 },
      { max_nesting: 3.0 }, { max_nesting: nil }].each do |limits|
      assert_raises(ArgumentError) { OrpcRails::RpcCodec.new(**limits) }
    end
  end

  def test_output_is_exact_json_and_unsupported_values_never_serialize
    assert_equal '{"json":{"name":"😀"},"meta":[]}', @codec.encode({ "name" => "😀" })
    cycle = []; cycle << cycle
    [Object.new, { name: "blue" }, Float::INFINITY, Float::NAN,
      9_007_199_254_740_992, 9_007_199_254_740_992.0, cycle, "\xFF".b].each do |value|
      assert_raises(OrpcRails::RpcCodec::Failure) { @codec.encode(value) }
    end
    value = +"blue"
    def value.to_json(*) = raise("custom JSON hook must not run")
    assert_equal '{"json":"blue","meta":[]}', @codec.encode(value)
  end

  def test_output_byte_depth_bounds_and_fixed_errors_at_minimum_limits
    codec = OrpcRails::RpcCodec.new(max_body_bytes: 1024, max_nesting: 3)
    assert_raises(OrpcRails::RpcCodec::Failure) { codec.encode('x' * 1024) }
    assert_raises(OrpcRails::RpcCodec::Failure) { codec.encode([[[0]]]) }
    OrpcRails::RpcCodec::ERRORS.each_key do |code|
      status, body = codec.failure(code)
      envelope = JSON.parse(body)
      assert_equal status, envelope.fetch("json").fetch("status")
      assert_equal false, envelope.fetch("json").fetch("defined")
      assert_equal({}, envelope.fetch("json").fetch("data"))
      assert_operator body.bytesize, :<=, 1024
      assert_equal envelope.fetch("json"), codec.decode(body)
    end
  end
end
