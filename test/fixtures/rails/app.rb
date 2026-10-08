# frozen_string_literal: true

require "action_controller/railtie"
require "orpc_rails"

class FixtureApplication < Rails::Application
  config.eager_load = false
  config.secret_key_base = "orpc-rails-test-fixture-only"
  config.hosts.clear
  config.logger = Logger.new($stderr, level: :warn)
end

class WidgetsController < ActionController::API
  include OrpcRails::Controller
  S = OrpcRails::Schema

  before_action :authenticate

  orpc_contract :show, key: "widgets.show", method: :get,
    path: "/widgets/:id", success_status: 200,
    input: S.object(
      params: S.object(id: S.string),
      query: S.object(search: S.string.optional).optional
    ),
    output: S.object(id: S.string, name: S.string, search: S.string.optional)

  orpc_contract :create, key: "widgets.create", method: :post,
    path: "/widgets", success_status: 201,
    input: S.object(body: S.object(widget: S.object(name: S.string))),
    output: S.object(id: S.string, name: S.string)

  def show
    result = { id: params[:id], name: "blue" }
    result[:search] = params[:search] if params.key?(:search)
    render json: result
  end

  def create
    name = params.require(:widget).permit(:name)[:name]
    if name == "invalid"
      render json: { errors: ["Name invalid"] }, status: :unprocessable_entity
    elsif name == "broken-output"
      render json: { id: "new" }, status: :created
    else
      render json: { id: "9007199254740993", name: name }, status: :created
    end
  end

  def destroy
    head :no_content
  end

  private

  def authenticate
    return if request.headers["x-fixture-token"] == "test-token"

    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end

class SchemaController < ActionController::API
  include OrpcRails::Controller
  S = OrpcRails::Schema
  FLAVOR = 'x"\\; globalThis.injected = true; // é'

  orpc_contract :show, key: "schema.show", method: :get, path: "/schema", success_status: 200,
    input: S.object,
    output: S.object(nickname: S.string.optional, note: S.string.nullable,
      count: S.integer(min: 0, max: 10), amount: S.number(min: 0, max: 2), flag: S.boolean,
      tag: S.literal("fixed"), flavor: S.enum(FLAVOR, "normal"),
      items: S.array(S.string(min_length: 1, max_length: 3), min_length: 1, max_length: 2))

  def show
    render json: { note: nil, count: 2, amount: 1.5, flag: true, tag: "fixed", flavor: FLAVOR, items: ["ok"] }
  end
end

class RpcFixtureController < ActionController::API
  include OrpcRails::Procedures
  wrap_parameters false
  S = OrpcRails::Schema
  class_attribute :handler_calls, default: 0
  class_attribute :context_calls, default: 0
  before_action :authenticate
  before_action :read_parameters_when_requested
  orpc_limits max_body_bytes: 1024, max_nesting: 6

  orpc_procedure "widgets.echo",
    input: S.object(name: S.string(min_length: 1, max_length: 20),
      note: S.string.nullable, nickname: S.string(max_length: 1).optional),
    output: S.object(id: S.string, name: S.string, note: S.string.nullable,
      nickname: S.string.optional) do |input:, context:|
    self.class.handler_calls += 1
    raise "simulated-secret" if input.fetch("name") == "explode"
    next { "id" => "broken" } if input.fetch("name") == "broken"
    next { "id" => "huge", "name" => "x" * 2048, "note" => nil } if input.fetch("name") == "oversized"
    { "id" => context.fetch(:id) }.merge(input)
  end

  orpc_procedure "probe.nullOutput", input: S.object, output: S.literal(nil) do
    nil
  end

  orpc_procedure "widgets.create", input: S.object(name: S.string), output: S.literal(nil),
    errors: { "CONFLICT" => { status: 409, data: S.object(name: S.string) } } do |input:, **|
    name = input.fetch("name")
    code = name == "undeclared" ? "UNKNOWN" : "CONFLICT"
    data = name == "invalid-error" ? {} : { "name" => name }
    message = name == "huge-error" ? "x" * 2048 : "Widget already exists"
    raise OrpcRails::Error.new(code, message: message, data: data)
  end

  private

  def read_parameters_when_requested
    params if request.headers["x-fixture-params"] == "read"
  end

  def orpc_context
    self.class.context_calls += 1
    { id: request.headers["x-fixture-id"] || "9007199254740993" }
  end

  def authenticate
    return if request.headers["x-fixture-token"] == "test-token"
    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end

FixtureApplication.initialize!
Rails.application.routes.draw do
  get "/health", to: ->(_) { [200, { "content-type" => "application/json" }, ['{"ok":true}']] }
  get "/schema", to: "schema#show"
  get "/widgets/:id", to: "widgets#show"
  post "/widgets", to: "widgets#create"
  delete "/widgets/:id", to: "widgets#destroy"
  unless ENV["ORPC_FIXTURE_MOUNT_RPC"] == "false"
    match "/rpc", to: "rpc_fixture#orpc_dispatch", via: :all, format: false
    match "/rpc/*orpc_path", to: "rpc_fixture#orpc_dispatch", via: :all, format: false
  end
end

if $PROGRAM_NAME == __FILE__
  require "rackup"
  require "webrick"
  Rackup::Handler::WEBrick.run(
    Rails.application, Host: "0.0.0.0", Port: 3000,
    AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
  )
end
