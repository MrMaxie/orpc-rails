# frozen_string_literal: true

require_relative "app"
require "rake"
require "minitest/autorun"
require "tmpdir"

Rails.application.load_tasks

class ExportTasksTest < Minitest::Test
  def invoke(name, path = nil, controller = nil)
    task = Rake::Task[name]
    task.reenable
    task.invoke(path, controller)
  end

  def test_tasks_require_an_explicit_destination
    assert_raises(ArgumentError) { invoke("orpc:export") }
    assert_raises(ArgumentError) { invoke("orpc:check") }
  end

  def test_rpc_tasks_require_both_destination_and_registered_controller
    %w[orpc:export_rpc orpc:check_rpc].each do |name|
      assert_raises(ArgumentError) { invoke(name) }
      assert_raises(ArgumentError) { invoke(name, "unused.ts") }
      assert_raises(ArgumentError) { invoke(name, "unused.ts", "String") }
    end
    refute File.exist?("unused.ts")
  end

  def test_rpc_tasks_export_check_and_keep_http_contract_separate
    Dir.mktmpdir do |directory|
      http_path, rpc_path = %w[http.ts rpc.ts].map { |name| File.join(directory, name) }
      invoke("orpc:export", http_path)
      http = File.binread(http_path)
      invoke("orpc:export_rpc", rpc_path, "RpcFixtureController")
      expected = File.binread(rpc_path)
      refute_includes expected, "oc.route"
      assert_includes expected, "widgets.create"
      invoke("orpc:check_rpc", rpc_path, "RpcFixtureController")
      assert_equal http, File.binread(http_path)
      File.binwrite(rpc_path, "stale")
      before = File.stat(rpc_path).mtime
      assert_raises(ArgumentError) { invoke("orpc:check_rpc", rpc_path, "RpcFixtureController") }
      assert_equal "stale", File.binread(rpc_path)
      assert_equal before, File.stat(rpc_path).mtime
    end
  end

  def test_export_then_check_and_nonwriting_drift_failure
    Dir.mktmpdir do |directory|
      path = File.join(directory, "contract.ts")
      invoke("orpc:export", path)
      expected = File.binread(path)
      timestamp = File.stat(path).mtime
      invoke("orpc:check", path)
      assert_equal expected, File.binread(path)
      assert_equal timestamp, File.stat(path).mtime
      File.binwrite(path, "stale")
      timestamp = File.stat(path).mtime
      error = assert_raises(ArgumentError) { invoke("orpc:check", path) }
      assert_includes error.message, "Contract drift"
      assert_equal "stale", File.binread(path)
      assert_equal timestamp, File.stat(path).mtime
      missing = File.join(directory, "missing.ts")
      assert_raises(ArgumentError) { invoke("orpc:check", missing) }
      refute File.exist?(missing)
    end
  end
end
