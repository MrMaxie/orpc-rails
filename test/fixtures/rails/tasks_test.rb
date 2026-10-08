# frozen_string_literal: true

require_relative "app"
require "rake"
require "minitest/autorun"
require "tmpdir"

Rails.application.load_tasks

class ExportTasksTest < Minitest::Test
  def invoke(name, path = nil)
    task = Rake::Task[name]
    task.reenable
    task.invoke(path)
  end

  def test_tasks_require_an_explicit_destination
    assert_raises(ArgumentError) { invoke("orpc:export") }
    assert_raises(ArgumentError) { invoke("orpc:check") }
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
