# frozen_string_literal: true

require_relative "lib/orpc_rails/version"

Gem::Specification.new do |spec|
  spec.name = "orpc-rails"
  spec.version = OrpcRails::VERSION
  spec.authors = ["Maxie"]
  spec.summary = "Export Rails endpoints as Zod and oRPC TypeScript contracts"
  spec.description = "Explicit, deterministic contracts for existing Rails JSON endpoints."
  spec.homepage = "https://github.com/MrMaxie/orpc-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "lib/**/*.rake"] + %w[LICENSE README.md CHANGELOG.md]
  end
  spec.require_paths = ["lib"]
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.add_dependency "actionpack", ">= 7.2", "< 9"
  spec.add_dependency "railties", ">= 7.2", "< 9"
  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "testcontainers", "= 0.2.0"
end
