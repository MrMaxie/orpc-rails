# frozen_string_literal: true

require "minitest/autorun"
require "rubygems/package"
require "tmpdir"
require "open3"
require "bundler"

class PackageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_gem_has_one_version_and_only_runtime_rails_dependencies
    spec = Gem::Specification.load(File.join(ROOT, "orpc-rails.gemspec"))
    refute_nil spec
    require_relative "../lib/orpc_rails/version"
    assert_equal OrpcRails::VERSION, spec.version.to_s
    assert_equal %w[actionpack railties], spec.runtime_dependencies.map(&:name).sort
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.3.0"))
    refute spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.2.0"))
  end

  def test_built_package_excludes_tests_and_loads_its_library
    spec = Gem::Specification.load(File.join(ROOT, "orpc-rails.gemspec"))
    refute_nil spec
    Dir.mktmpdir("orpc-package") do |dir|
      artifact = File.join(dir, "orpc-rails.gem")
      Dir.chdir(ROOT) { Gem::Package.build(spec, false, false, artifact) }
      package = Gem::Package.new(artifact)
      files = package.contents
      assert_includes files, "lib/orpc_rails.rb"
      assert_includes files, "LICENSE"
      assert_includes files, "README.md"
      assert_includes files, "CHANGELOG.md"
      assert files.all? { |file| file.start_with?("lib/") || %w[LICENSE README.md CHANGELOG.md].include?(file) }
      refute files.any? { |file| file.match?(%r{(?:test|spec|openspec|node_modules|vendor|\.local)/}) }
      package.extract_files(File.join(dir, "installed"))
      output, status = Bundler.with_unbundled_env do
        Open3.capture2e(
          { "RUBYOPT" => nil, "RUBYLIB" => nil },
          Gem.ruby, "-I#{dir}/installed/lib", "-e",
          'require "orpc_rails"; abort "Missing export API" unless OrpcRails.const_defined?(:Controller) && OrpcRails.const_defined?(:Exporter) && OrpcRails.const_defined?(:Railtie); puts OrpcRails::VERSION'
        )
      end
      assert status.success?, output
      assert_equal spec.version.to_s, output.strip
    end
  end
end
