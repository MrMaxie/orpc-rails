# frozen_string_literal: true

require "minitest/autorun"
require "action_controller"
require_relative "../lib/orpc_rails/controller"

class ContractFixtureController < ActionController::API
  include OrpcRails::Controller

  def show
    render json: { id: params[:id] }
  end
end

class ControllerTest < Minitest::Test
  def setup
    ContractFixtureController.instance_variable_set(:@orpc_contracts, nil)
  end

  def test_declaration_is_immutable_and_does_not_add_callbacks_or_actions
    before = ContractFixtureController._process_action_callbacks.to_a
    actions = ContractFixtureController.action_methods.to_a.sort
    schema = Object.new.freeze
    path = +"/widgets/:id"
    endpoint = ContractFixtureController.orpc_contract(:show,
      key: "widgets.show", method: :get, path: path,
      input: schema, output: schema, success_status: 200)
    path.replace("/changed")

    assert_equal "/widgets/:id", endpoint.path
    assert_equal "GET", endpoint.http_method
    assert_same schema, endpoint.input
    assert endpoint.frozen?
    assert ContractFixtureController.orpc_contracts.frozen?
    assert_equal before, ContractFixtureController._process_action_callbacks.to_a
    assert_equal actions, ContractFixtureController.action_methods.to_a.sort
    assert_includes OrpcRails.registry.endpoints, endpoint
  end

  def test_undeclared_subclass_does_not_inherit_wrong_controller_registration
    ContractFixtureController.orpc_contract(:show, key: "widgets.show", method: :get,
      path: "/widgets/:id", input: nil, output: nil, success_status: 200)
    child = Class.new(ContractFixtureController)
    assert_empty child.orpc_contracts
  end

  def test_repeated_declarations_are_retained_for_export_collision_validation
    2.times do
      ContractFixtureController.orpc_contract(:show, key: "widgets.show", method: :get,
        path: "/widgets/:id", input: nil, output: nil, success_status: 200)
    end
    assert_equal 2, ContractFixtureController.orpc_contracts.size
  end
end
