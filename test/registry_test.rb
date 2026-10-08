# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/orpc_rails/registry"

class RegistryTest < Minitest::Test
  def setup
    @registry = OrpcRails::Registry.new
    Object.const_set(:RegistryFixtureController, Class.new do
      def self.orpc_contracts = [:current]
    end)
  end

  def teardown
    Object.send(:remove_const, :RegistryFixtureController) if Object.const_defined?(:RegistryFixtureController)
  end

  def test_registration_is_idempotent
    2.times { @registry.register(RegistryFixtureController) }
    assert_equal [:current], @registry.endpoints
    assert @registry.endpoints.frozen?
  end

  def test_reloaded_class_replaces_previous_declarations
    @registry.register(RegistryFixtureController)
    Object.send(:remove_const, :RegistryFixtureController)
    Object.const_set(:RegistryFixtureController, Class.new do
      def self.orpc_contracts = [:reloaded]
    end)
    @registry.register(RegistryFixtureController)
    assert_equal [:reloaded], @registry.endpoints
  end

  def test_removed_class_is_not_exported
    @registry.register(RegistryFixtureController)
    Object.send(:remove_const, :RegistryFixtureController)
    assert_empty @registry.endpoints
  end

  def test_anonymous_controllers_fail_explicitly
    assert_raises(ArgumentError) { @registry.register(Class.new) }
  end
end
