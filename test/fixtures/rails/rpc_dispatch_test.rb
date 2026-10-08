# frozen_string_literal: true

require_relative "app"
require "minitest/autorun"
require "rack/mock"

Rails.logger.level = Logger::WARN

class SecureRpcDispatchController < ActionController::Base
  include OrpcRails::Procedures
  wrap_parameters false
  self.allow_forgery_protection = true
  protect_from_forgery with: :exception
  class_attribute :handler_calls, default: 0
  orpc_procedure "echo", input: OrpcRails::Schema.object, output: OrpcRails::Schema.boolean do
    self.class.handler_calls += 1
    true
  end

  def token
    render json: { token: form_authenticity_token }
  end
end

class OtherRpcDispatchController < ActionController::API
  include OrpcRails::Procedures
  wrap_parameters false
  orpc_procedure "other.only", input: OrpcRails::Schema.object, output: OrpcRails::Schema.literal("other") do
    "other"
  end
  orpc_procedure "widgets.echo", input: OrpcRails::Schema.object, output: OrpcRails::Schema.literal("other echo") do
    "other echo"
  end
end

# Isolated process: these routes do not alter the separately running HTTP app.
Rails.application.routes.draw do
  match "/rpc", to: "rpc_fixture#orpc_dispatch", via: :all, format: false
  match "/rpc/*orpc_path", to: "rpc_fixture#orpc_dispatch", via: :all, format: false
  get "/secure/token", to: "secure_rpc_dispatch#token"
  match "/secure/*orpc_path", to: "secure_rpc_dispatch#orpc_dispatch", via: :all, format: false
  match "/other/*orpc_path", to: "other_rpc_dispatch#orpc_dispatch", via: :all, format: false
end

class RpcDispatchTest < Minitest::Test
  def setup
    @http = Rack::MockRequest.new(Rails.application)
    RpcFixtureController.handler_calls = 0
    RpcFixtureController.context_calls = 0
  end

  def request(body = '{"json":{"name":"blue","note":null}}', path: "/rpc/widgets/echo", method: "POST", **headers)
    @http.request(method, path, { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json",
      "HTTP_X_FIXTURE_TOKEN" => "test-token", input: body }.merge(headers))
  end

  def failure(response, code, status)
    assert_equal status, response.status
    error = JSON.parse(response.body).fetch("json")
    assert_equal code, error.fetch("code")
    assert_equal status, error.fetch("status")
    assert_equal false, error.fetch("defined")
    assert_equal({}, error.fetch("data"))
    assert_equal [], JSON.parse(response.body).fetch("meta")
    refute_includes response.body, "simulated-secret"
  end

  def test_echo_and_absolute_request_uri_from_webrick
    response = request("{\"json\":{\"name\":\"blue\",\"note\":null}}", "REQUEST_URI" => "http://rails:3000/rpc/widgets/echo")
    assert_equal 200, response.status
    assert_equal({ "id" => "9007199254740993", "name" => "blue", "note" => nil }, JSON.parse(response.body).fetch("json"))
    assert_equal 1, RpcFixtureController.context_calls
    assert_equal 1, RpcFixtureController.handler_calls
  end

  def test_bad_input_and_envelope_never_build_context_or_call_handler
    ['{"json":', '{"json":{"name":"blue","note":null,"extra":1}}',
      '{"json":{"name":"blue"}}', '{"json":{"name":42,"note":null}}',
      '{"json":{"name":"blue","note":null,"nickname":"e\\u0301"}}',
      '{"json":1,"json":2}', '{"json":null,"meta":[[1]]}', '{"json":null,"maps":{}}',
      '{"json":{"a":1,"\\u0061":2}}',
      '{"json":9007199254740992}', '{"json":9007199254740992.0}',
      '{"json":9.007199254740992e15}', '{"json":1e400}',
      '{"json":/*comment*/null}', '{"json":"\\x61"}', '{"json":null,}',
      '{"json":[null,]}', '{"json":"\\uD800"}',
      '{"json":' + '[' * 6 + '0' + ']' * 6 + '}'].each do |body|
      failure(request(body), "BAD_REQUEST", 400)
    end
    assert_equal 0, RpcFixtureController.context_calls
    assert_equal 0, RpcFixtureController.handler_calls
  end

  def test_earlier_rails_encoding_rejection_is_preserved
    ["{\"json\":\"\xFF\"}".b, '{"json":"\\uDC00"}'].each do |body|
      assert_equal 400, request(body).status
    end
    assert_equal 0, RpcFixtureController.context_calls
    assert_equal 0, RpcFixtureController.handler_calls
  end

  def test_size_is_checked_for_cached_and_missing_or_misleading_length
    body = '{"json":"' + 'x' * 1024 + '"}'
    [{}, { "CONTENT_LENGTH" => "1", "RAW_POST_DATA" => body }].each do |headers|
      failure(request(body, **headers), "PAYLOAD_TOO_LARGE", 413)
    end
    assert_equal 0, RpcFixtureController.context_calls
    assert_equal 0, RpcFixtureController.handler_calls
  end

  def test_method_media_and_unknown_paths
    %w[GET PUT PATCH DELETE OPTIONS].each do |method|
      response = request(method: method)
      failure(response, "METHOD_NOT_SUPPORTED", 405)
      assert_equal "POST", response.headers["allow"]
    end
    failure(request("{}", "CONTENT_TYPE" => "text/plain"), "UNSUPPORTED_MEDIA_TYPE", 415)
    %w[/rpc /rpc/widgets/missing /rpc/widgets/echo/ /rpc/widgets.echo /rpc/widgets/%65cho /rpc/widgets//echo /rpc/widgets/./echo /rpc/widgets/../widgets/echo].each do |path|
      failure(request(path: path, "REQUEST_URI" => path), "NOT_FOUND", 404)
    end
    assert_equal 0, RpcFixtureController.context_calls
    assert_equal 0, RpcFixtureController.handler_calls
  end

  def test_callback_denial_remains_rails_owned
    response = request('{"json":', "HTTP_X_FIXTURE_TOKEN" => "denied")
    assert_equal 401, response.status
    assert_equal({ "error" => "Unauthorized" }, JSON.parse(response.body))
    assert_equal 0, RpcFixtureController.context_calls
    assert_equal 0, RpcFixtureController.handler_calls
  end

  def test_safe_exception_invalid_output_and_output_limit
    %w[explode broken oversized].each do |name|
      failure(request(JSON.generate("json" => { "name" => name, "note" => nil })), "INTERNAL_SERVER_ERROR", 500)
    end
  end

  def test_parameter_reading_callback_preserves_raw_body_and_earlier_failure
    response = request("{\"json\":{\"name\":\"blue\",\"note\":null}}", "HTTP_X_FIXTURE_PARAMS" => "read")
    assert_equal 200, response.status
    assert_equal "blue", JSON.parse(response.body).fetch("json").fetch("name")
    before_context, before_handler = RpcFixtureController.context_calls, RpcFixtureController.handler_calls
    assert_equal 400, request('{"json":', "HTTP_X_FIXTURE_PARAMS" => "read").status
    assert_equal before_context, RpcFixtureController.context_calls
    assert_equal before_handler, RpcFixtureController.handler_calls
  end

  def test_registered_keys_are_scoped_to_the_mounted_controller
    failure(request('{"json":{}}', path: "/rpc/other/only"), "NOT_FOUND", 404)
    other = request('{"json":{}}', path: "/other/widgets/echo")
    assert_equal 200, other.status
    assert_equal "other echo", JSON.parse(other.body).fetch("json")
    assert_equal 0, RpcFixtureController.handler_calls
    assert_equal 0, RpcFixtureController.context_calls
  end

  def test_actual_dispatch_preserves_csrf_denial_and_accepts_valid_token
    SecureRpcDispatchController.handler_calls = 0
    token_response = @http.get("/secure/token")
    assert_equal 200, token_response.status
    token = JSON.parse(token_response.body).fetch("token")
    cookies = Array(token_response.headers.fetch("set-cookie")).map { |cookie| cookie.split(";", 2).first }.join("; ")
    assert_equal 422, request('{"json":{}}', path: "/secure/echo", "HTTP_COOKIE" => cookies).status
    assert_equal 0, SecureRpcDispatchController.handler_calls
    response = request('{"json":{}}', path: "/secure/echo", "HTTP_COOKIE" => cookies, "HTTP_X_CSRF_TOKEN" => token)
    assert_equal 200, response.status
    assert_equal({ "json" => true, "meta" => [] }, JSON.parse(response.body))
    assert_equal 1, SecureRpcDispatchController.handler_calls
  end

  def test_actual_declared_error_envelope_matches_http_status
    response = request('{"json":{"name":"blue"}}', path: "/rpc/widgets/create")
    assert_equal 409, response.status
    assert_equal({ "json" => { "defined" => true, "code" => "CONFLICT", "status" => 409,
      "message" => "Widget already exists", "data" => { "name" => "blue" } }, "meta" => [] }, JSON.parse(response.body))
  end

  def test_context_is_created_for_each_accepted_request_only
    %w[first second].each do |id|
      response = request("{\"json\":{\"name\":\"blue\",\"note\":null}}", "HTTP_X_FIXTURE_ID" => id)
      assert_equal 200, response.status
      assert_equal id, JSON.parse(response.body).fetch("json").fetch("id")
    end
    assert_equal 2, RpcFixtureController.context_calls
    assert_equal 2, RpcFixtureController.handler_calls
  end
end
