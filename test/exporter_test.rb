# frozen_string_literal: true

require "minitest/autorun"
require "action_controller"
require "tmpdir"
require_relative "../lib/orpc_rails/schema"
require_relative "../lib/orpc_rails/controller"
require_relative "../lib/orpc_rails/exporter"

class ExportFixtureController < ActionController::API
  def show; end
  def create; end
end

class ExporterTest < Minitest::Test
  S = OrpcRails::Schema

  def setup
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      get "/widgets/:id", to: "export_fixture#show"
      post "/widgets", to: "export_fixture#create"
    end
  end

  def endpoint(**changes)
    OrpcRails::Endpoint.new(**{
      controller: ExportFixtureController, action: :show, key: "widgets.show",
      method: :get, path: "/widgets/:id", success_status: 200,
      input: S.object(params: S.object(id: S.string), query: S.object(search: S.string.optional).optional),
      output: S.object(id: S.string, name: S.string)
    }.merge(changes))
  end

  def exporter(*endpoints)
    OrpcRails::Exporter.new(routes: @routes, endpoints: endpoints)
  end

  def test_generated_module_has_executable_schemas_and_detailed_v1_contract
    source = exporter(endpoint).generate
    assert_includes source, 'import * as z from "zod"'
    assert_includes source, 'import { oc } from "@orpc/contract"'
    assert_includes source, '"path":"/widgets/{id}"'
    assert_includes source, '"inputStructure":"detailed"'
    assert_includes source, 'schemas["widgets.show"].input'
    assert_includes source, 'export type Contract = typeof contract'
    refute_includes source, "\r"
  end

  def test_registration_order_does_not_change_bytes
    create = endpoint(action: :create, key: "widgets.create", method: :post, path: "/widgets",
      success_status: 201, input: S.object(body: S.object(widget: S.object(name: S.string))))
    assert_equal exporter(endpoint, create).generate, exporter(create, endpoint).generate
  end

  def test_rejects_router_duplicates_prefixes_and_reserved_segments
    [endpoint, endpoint(key: "widgets"), endpoint(key: "widgets.then"),
      endpoint(key: "__proto__.show"), endpoint(key: "widgets..show")].each do |bad|
      assert_raises(ArgumentError) { exporter(endpoint, bad).generate }
    end
  end

  def test_rejects_unsupported_input_mapping_and_names_error_location
    bad_inputs = [S.string, S.object(params: S.object(id: S.integer)),
      S.object(params: S.object(id: S.string.optional)), S.object(params: S.object(other: S.string)),
      S.object(params: S.object(id: S.string), body: S.object),
      S.object(params: S.object(id: S.string), query: S.object(q: S.string.nullable)),
      S.object(params: S.object(id: S.string), query: S.object(q: S.array(S.string))),
      S.object(params: S.object(id: S.string), headers: S.object(Authorization: S.string)),
      S.object(params: S.object(id: S.string), cookie: S.string)]
    bad_inputs.each do |input|
      error = assert_raises(ArgumentError) { exporter(endpoint(input: input)).generate }
      assert_includes error.message, "widgets.show"
    end
    assert_raises(ArgumentError) { exporter(endpoint(output: S.string.optional)).generate }
    assert_raises(ArgumentError) { exporter(endpoint(success_status: 204)).generate }
    assert_raises(ArgumentError) { exporter(endpoint(method: :head)).generate }
    assert_raises(ArgumentError) { exporter(endpoint(path: "/widgets/*id")).generate }
    assert_raises(ArgumentError) { exporter(endpoint(action: :create)).generate }
  end

  def test_atomic_export_and_nonwriting_drift_check
    Dir.mktmpdir do |dir|
      path = File.join(dir, "contract.ts")
      current = exporter(endpoint)
      current.write(path)
      assert_equal current.generate, File.binread(path)
      assert current.check(path)
      before = File.stat(path).mtime
      invalid = exporter(endpoint, endpoint)
      assert_raises(ArgumentError) { invalid.write(path) }
      File.binwrite(path, "stale")
      stale_time = File.stat(path).mtime
      assert_raises(ArgumentError) { current.check(path) }
      assert_equal "stale", File.binread(path)
      assert_equal stale_time, File.stat(path).mtime
      refute_nil before
    end
  end
end
