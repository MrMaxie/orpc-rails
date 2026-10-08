# frozen_string_literal: true

ENV["ORPC_FIXTURE_MOUNT_RPC"] = "false"
require_relative "app"
require "minitest/autorun"
require "rack/mock"
Rails.logger.level = Logger::WARN

class UnmountedRpcTest < Minitest::Test
  def test_declared_but_unmounted_procedures_leave_http_endpoints_unchanged
    http = Rack::MockRequest.new(Rails.application)
    response = http.get("/widgets/42", "HTTP_X_FIXTURE_TOKEN" => "test-token")
    assert_equal 200, response.status
    assert_equal({ "id" => "42", "name" => "blue" }, JSON.parse(response.body))
    assert_equal 404, http.post("/rpc/widgets/echo", "CONTENT_TYPE" => "application/json",
      "HTTP_X_FIXTURE_TOKEN" => "test-token", input: '{"json":{"name":"blue","note":null}}').status
    assert_equal 0, RpcFixtureController.handler_calls
    assert_equal 0, RpcFixtureController.context_calls
    refute_includes WidgetsController.action_methods, "orpc_dispatch"
  end
end
