# frozen_string_literal: true

require "minitest/autorun"
require "action_controller"
require "tmpdir"
require_relative "../lib/orpc_rails/procedures"
require_relative "../lib/orpc_rails/rpc_exporter"

class ProcedureFixtureController < ActionController::API
  include OrpcRails::Procedures
  wrap_parameters false
end
class OtherProcedureFixtureController < ActionController::API
  include OrpcRails::Procedures
  wrap_parameters false
end

class ProceduresTest < Minitest::Test
  S = OrpcRails::Schema

  def setup
    [ProcedureFixtureController, OtherProcedureFixtureController].each do |controller|
      controller.instance_variable_set(:@orpc_procedures, nil)
    end
  end

  def declare(controller = ProcedureFixtureController, key = "widgets.echo", **overrides, &block)
    controller.orpc_procedure(key, **{ input: S.object(name: S.string), output: S.object(name: S.string) }.merge(overrides),
      &(block || ->(input:, context:) { raise "Export must not call handlers" }))
  end

  def test_immutable_declarations_selected_export_and_no_http_metadata
    endpoint = declare
    declare(OtherProcedureFixtureController, "other.echo")
    assert endpoint.frozen?
    assert ProcedureFixtureController.orpc_procedures.frozen?
    assert_equal [:orpc_dispatch], (ProcedureFixtureController.action_methods.to_a.map(&:to_sym) & [:orpc_dispatch, :orpc_context])
    source = OrpcRails::RpcExporter.new(controller: "ProcedureFixtureController").generate
    assert_includes source, '"widgets": {"echo": oc.input('
    assert_includes source, 'export type Contract = typeof contract'
    refute_includes source, "oc.route"
    refute_includes source, "other.echo"
    assert_empty Class.new(ProcedureFixtureController).orpc_procedures
  end

  def test_invalid_declarations_and_collisions_are_rejected_without_mutating
    declare
    %w[widgets.echo widgets widgets.echo.child widgets.then widgets..bad].each do |key|
      assert_raises(ArgumentError) { declare(ProcedureFixtureController, key) }
    end
    [ { input: S.string.optional }, { output: Object.new },
      { errors: { "" => { status: 409, data: S.object } } },
      { errors: { "CONFLICT" => { status: 409.0, data: S.object } } },
      { errors: { "CONFLICT" => { status: 200, data: S.object } } },
      { errors: { "CONFLICT" => { status: 409, data: S.string.optional } } } ].each do |changes|
      assert_raises(ArgumentError) { declare(ProcedureFixtureController, "new.echo", **changes) }
    end
    assert_equal 1, ProcedureFixtureController.orpc_procedures.size
    assert_raises(ArgumentError) { Class.new(ProcedureFixtureController).orpc_procedure("echo", input: S.object, output: S.object) { } }
    assert_raises(ArgumentError) { ProcedureFixtureController.orpc_procedure("new.echo", input: S.object, output: S.object) }
  end

  def test_error_metadata_is_copied_and_exported
    code = +"CONFLICT"
    errors = { code => { status: 409, data: S.object(name: S.string) } }
    endpoint = declare(errors: errors)
    code.replace("CHANGED")
    errors.clear
    assert_equal 409, endpoint.errors.fetch("CONFLICT").fetch(:status)
    assert endpoint.errors.frozen?
    source = OrpcRails::RpcExporter.new(controller: "ProcedureFixtureController").generate
    assert_includes source, '.errors({"CONFLICT": { status: 409, data: z.strictObject('
  end

  def test_atomic_export_drift_and_missing_or_unregistered_controller
    declare
    exporter = OrpcRails::RpcExporter.new(controller: "ProcedureFixtureController")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "rpc.ts")
      exporter.write(path)
      assert exporter.check(path)
      File.binwrite(path, "stale")
      before = File.stat(path).mtime
      assert_raises(ArgumentError) { exporter.check(path) }
      assert_equal "stale", File.binread(path)
      assert_equal before, File.stat(path).mtime
      assert_raises(ArgumentError) { exporter.check(File.join(dir, "missing.ts")) }
    end
    ["String", "NotARegisteredController", "OtherProcedureFixtureController"].each do |name|
      assert_raises(ArgumentError) { OrpcRails::RpcExporter.new(controller: name).generate }
    end
  end

  def test_registry_resolves_reloaded_controller_instead_of_stale_class
    declare
    Object.const_set(:ReloadProcedureController, Class.new(ProcedureFixtureController))
    declare(ReloadProcedureController, "before.echo")
    old = ReloadProcedureController
    Object.send(:remove_const, :ReloadProcedureController)
    Object.const_set(:ReloadProcedureController, Class.new(ProcedureFixtureController))
    declare(ReloadProcedureController, "after.echo")
    source = OrpcRails::RpcExporter.new(controller: "ReloadProcedureController").generate
    assert_includes source, "after.echo"
    refute_includes source, "before.echo"
    refute_same old, ReloadProcedureController
  ensure
    Object.send(:remove_const, :ReloadProcedureController) if Object.const_defined?(:ReloadProcedureController)
  end
end
