# frozen_string_literal: true

require "minitest/autorun"
require "action_controller/railtie"
require_relative "../lib/orpc_rails/routes"

class RouteFixtureController < ActionController::API
  def show = nil
  def create = nil
end

class RoutesTest < Minitest::Test
  Endpoint = Struct.new(:key, :controller, :action, :http_method, :path, keyword_init: true)

  def setup
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      get "/widgets/:id", to: "route_fixture#show"
      post "/widgets", to: "route_fixture#create"
      get "/limited/:id", to: "route_fixture#show", constraints: { id: /\d+/ }
      get "/hidden", to: "route_fixture#show", constraints: ->(_) { false }
    end
  end

  def endpoint(**changes)
    Endpoint.new(**{ key: "widgets.show", controller: RouteFixtureController,
      action: "show", http_method: "GET", path: "/widgets/:id" }.merge(changes))
  end

  def test_accepts_the_standard_rails_format_suffix_without_exporting_it
    assert OrpcRails::Routes.new(@routes).validate!(endpoint)
  end

  def test_route_must_match_the_controller_action_and_method
    validator = OrpcRails::Routes.new(@routes)
    assert_raises(ArgumentError) { validator.validate!(endpoint(action: "create")) }
    assert_raises(ArgumentError) { validator.validate!(endpoint(http_method: "POST")) }
    assert_raises(ArgumentError) { validator.validate!(endpoint(path: "/missing/:id")) }
  end

  def test_parameter_and_request_constraints_are_not_guessed
    validator = OrpcRails::Routes.new(@routes)
    assert_raises(ArgumentError) { validator.validate!(endpoint(path: "/limited/:id")) }
    assert_raises(ArgumentError) { validator.validate!(endpoint(path: "/hidden")) }
  end
end
