# frozen_string_literal: true

require_relative "app"
require "minitest/autorun"
require "json"
require "rack/mock"

class RpcRawProbeController < ActionController::API
  wrap_parameters false
  class_attribute :raw_calls, default: 0
  before_action :authenticate
  before_action :optional_params_read

  def raw_body
    self.class.raw_calls += 1
    first = request.raw_post
    render json: { raw: first, repeated: request.raw_post == first }
  end

  private

  def authenticate
    render json: { denied: true }, status: :unauthorized unless request.headers["x-probe-auth"] == "allowed"
  end

  def optional_params_read
    params if request.headers["x-probe-params"] == "read"
  end
end

class RpcCsrfProbeController < ActionController::Base
  wrap_parameters false
  self.allow_forgery_protection = true
  protect_from_forgery with: :exception
  class_attribute :raw_calls, default: 0

  def token
    render json: { token: form_authenticity_token }
  end

  def raw_body
    self.class.raw_calls += 1
    render json: { raw: request.raw_post }
  end
end

# This probe runs in its own process; normal HTTP fixture routes are unchanged.
Rails.application.config.log_level = :warn
Rails.application.routes.draw do
  post "/rpc-probe/raw", to: "rpc_raw_probe#raw_body"
  get "/rpc-probe/csrf-token", to: "rpc_csrf_probe#token"
  post "/rpc-probe/csrf", to: "rpc_csrf_probe#raw_body"
end

# Prerequisite probes only, not the gem's RPC codec or procedure adapter.
# Observe parser differences instead of claiming a secure decoder exists.
class RpcParserPrerequisitesTest < Minitest::Test
  class AssignmentCapture
    attr_reader :writes
    def initialize = @writes = []
    def []=(key, value)
      @writes << [key, value]
    end
  end

  class MustNotConstruct
    def self.json_create(_)
      raise "JSON additions must not construct this class"
    end
  end

  def parser_options
    # json 3 removed this option together with additions; passing it now raises.
    JSON::VERSION.split('.').first.to_i < 3 ? { create_additions: false } : {}
  end

  def test_duplicate_detection_cannot_rely_on_object_class_across_json_versions
    source = '{"json":1,"json":2}'
    assert_equal({ "json" => 2 }, JSON.parse(source, **parser_options, allow_duplicate_key: true))
    captured = JSON.parse(source, **parser_options, object_class: AssignmentCapture, allow_duplicate_key: true)
    assert_includes [1, 2], captured.writes.size
    assert_equal ["json", 2], captured.writes.last
    native_rejection = begin
      JSON.parse(source, **parser_options, allow_duplicate_key: false)
      false
    rescue JSON::ParserError
      true
    end
    puts JSON.generate(ruby: RUBY_VERSION, rails: Rails.version, json: JSON::VERSION,
      object_class_assignments: captured.writes.size, native_duplicate_rejection: native_rejection)
  end

  def test_json_additions_are_disabled_or_removed
    source = '{"json_class":"RpcParserPrerequisitesTest::MustNotConstruct"}'
    assert_equal({ "json_class" => "RpcParserPrerequisitesTest::MustNotConstruct" },
      JSON.parse(source, **parser_options))
    if JSON::VERSION.split('.').first.to_i >= 3
      assert_raises(ArgumentError) { JSON.parse(source, create_additions: false) }
    end
  end

  def test_raw_and_decoded_encoding_need_independent_guards
    raw = "{\"json\":\"\xFF\"}".b
    refute raw.dup.force_encoding(Encoding::UTF_8).valid_encoding?
    [raw, '"\uD800"', '"\uDC00"'].each do |source|
      outcome = begin
        parsed = JSON.parse(source, **parser_options)
        strings = parsed.is_a?(Hash) ? parsed.values : [parsed]
        strings.all?(&:valid_encoding?) ? "accepted_valid" : "accepted_invalid"
      rescue JSON::ParserError, ArgumentError
        "rejected"
      end
      refute_equal "accepted_valid", outcome
    end
    assert_equal "\u{1F600}", JSON.parse('"\uD83D\uDE00"', **parser_options)
  end

  def test_depth_counts_the_wire_envelope_and_array_or_object_containers
    value_at_63 = "[" * 63 + "0" + "]" * 63
    value_at_64 = "[" * 64 + "0" + "]" * 64
    assert JSON.parse('{"json":' + value_at_63 + '}', **parser_options, max_nesting: 64)
    assert_raises(JSON::NestingError) do
      JSON.parse('{"json":' + value_at_64 + '}', **parser_options, max_nesting: 64)
    end
  end

  def test_numeric_profile_is_separate_from_json_parsing
    assert_equal 9_007_199_254_740_992, JSON.parse("9007199254740992")
    assert_equal 9_007_199_254_740_992.0, JSON.parse("9007199254740992.0")
    refute JSON.parse("1e400").finite?
    assert_raises(JSON::ParserError) { JSON.parse("NaN", allow_nan: false) }
    assert_raises(JSON::GeneratorError) { JSON.generate(Float::INFINITY, allow_nan: false) }
  end

  def test_string_bounds_use_unicode_codepoints_matching_pinned_zod
    astral = "\u{1F600}"
    assert_equal 1, astral.length
    assert_equal 2, astral.encode(Encoding::UTF_16LE).bytesize / 2
    assert_equal 2, "e\u0301".length
    assert_equal 1, "\u00E9".length
  end
end

class RpcRailsLifecyclePrerequisitesTest < Minitest::Test
  def setup
    @http = Rack::MockRequest.new(Rails.application)
    RpcRawProbeController.raw_calls = 0
    RpcCsrfProbeController.raw_calls = 0
  end

  def post(path, body, **headers)
    @http.post(path, { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json", input: body }.merge(headers))
  end

  def test_raw_body_is_available_after_callbacks_even_when_json_is_malformed
    malformed = '{"json":'
    response = post("/rpc-probe/raw", malformed, "HTTP_X_PROBE_AUTH" => "allowed")
    assert_equal 200, response.status
    assert_equal({ "raw" => malformed, "repeated" => true }, JSON.parse(response.body))
    assert_equal 1, RpcRawProbeController.raw_calls
  end

  def test_raw_body_survives_a_callback_that_reads_valid_rails_params
    body = '{"json":{"name":"blue"}}'
    response = post("/rpc-probe/raw", body, "HTTP_X_PROBE_AUTH" => "allowed", "HTTP_X_PROBE_PARAMS" => "read")
    assert_equal 200, response.status
    assert_equal body, JSON.parse(response.body).fetch("raw")
    assert_equal 1, RpcRawProbeController.raw_calls
  end

  def test_denial_is_application_owned_before_the_raw_body_action
    response = post("/rpc-probe/raw", '{"json":')
    assert_equal 401, response.status
    assert_equal({ "denied" => true }, JSON.parse(response.body))
    assert_equal 0, RpcRawProbeController.raw_calls
  end

  def test_params_parse_failure_can_happen_before_the_raw_body_action
    response = post("/rpc-probe/raw", '{"json":', "HTTP_X_PROBE_AUTH" => "allowed", "HTTP_X_PROBE_PARAMS" => "read")
    assert_equal 400, response.status
    assert_equal 0, RpcRawProbeController.raw_calls
  end

  def test_valid_and_missing_csrf_tokens_keep_rails_policy
    token_response = @http.get("/rpc-probe/csrf-token")
    assert_equal 200, token_response.status
    token = JSON.parse(token_response.body).fetch("token")
    cookies = Array(token_response.headers.fetch("set-cookie")).map { |cookie| cookie.split(";", 2).first }.join("; ")
    body = '{"json":{}}'
    denied = post("/rpc-probe/csrf", body, "HTTP_COOKIE" => cookies)
    assert_equal 422, denied.status
    assert_equal 0, RpcCsrfProbeController.raw_calls
    accepted = post("/rpc-probe/csrf", body, "HTTP_COOKIE" => cookies, "HTTP_X_CSRF_TOKEN" => token)
    assert_equal 200, accepted.status
    assert_equal body, JSON.parse(accepted.body).fetch("raw")
    assert_equal 1, RpcCsrfProbeController.raw_calls
  end
end
