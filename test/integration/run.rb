# frozen_string_literal: true

require "testcontainers"
require "securerandom"
require "timeout"

# testcontainers-core 0.2.0 always pulls in #start, even for locally built
# images. Keep its lifecycle/ports/copy/exec helpers, but start our prebuilt
# fixture images without a registry pull. This is test infrastructure only.
class FixtureContainer < Testcontainers::DockerContainer
  # 0.2.0's container gateway discovery overrides TC_HOST; our runner uses
  # Docker's explicit host-gateway mapping for ephemeral published ports.
  def host
    ENV.fetch("TC_HOST")
  end

  def start
    Docker::Image.get(image)
    @_container = Docker::Container.create(send(:_container_create_options))
    @_container.start
    @_id = @_container.id
    @wait_for&.call(self)
    self
  end
end

def execute!(container, command)
  stdout, stderr, code = container.exec(command)
  raise "Fixture command failed: #{command.join(' ')}\n#{stdout.join}\n#{stderr.join}" unless code.zero?

  puts stdout.join unless stdout.empty?
  stdout.join
end

run_id = SecureRandom.hex(8)
network = nil
containers = []
Signal.trap("TERM") { raise Interrupt }

begin
  raise "Docker did not answer its health probe" unless Docker.ping == "OK"
  network = Docker::Network.create("orpc-rails-#{run_id}", "Labels" => { "orpc-rails-suite" => run_id })
  rails = FixtureContainer.new(ENV.fetch("RAILS_IMAGE"))
    .with_exposed_port(3000)
    .with_labels("orpc-rails-suite" => run_id)
    .with_wait_for(->(_) { true })
  containers << rails
  rails.start
  network.connect(rails._id, {}, "EndpointConfig" => { "Aliases" => ["rails"] })
  rails.store_file("/fixture/orpc-rails.gem", File.binread("orpc-rails.gem"))
  execute!(rails, %w[gem install /fixture/orpc-rails.gem --local --no-document])
  execute!(rails, %w[mkdir -p /fixture/test])
  Dir["test/*_test.rb"].each { |file| rails.store_file("/fixture/#{file}", File.binread(file)) }
  Dir["distribution/*"].each do |file|
    rails.store_file("/fixture/#{File.basename(file)}", File.binread(file))
  end
  execute!(rails, ["ruby", "-e", 'require "fileutils"; require "rubygems"; FileUtils.ln_s(Gem::Specification.find_by_name("orpc-rails").full_gem_path + "/lib", "/fixture/lib")'])
  execute!(rails, ["ruby", "-Ilib", "-e", 'Dir["test/*_test.rb"].sort.each { |file| require_relative file }'])
  execute!(rails, ["ruby", "tasks_test.rb"])
  execute!(rails, ["ruby", "rpc_prerequisites_test.rb"])
  execute!(rails, ["ruby", "rpc_dispatch_test.rb"])
  execute!(rails, ["ruby", "unmounted_test.rb"])
  first = execute!(rails, ["ruby", "-r./app", "-e", 'print OrpcRails::Exporter.new(routes: Rails.application.routes).generate'])
  second = execute!(rails, ["ruby", "-r./app", "-e", 'print OrpcRails::Exporter.new(routes: Rails.application.routes).generate'])
  raise "Generated contracts differ between fresh processes" unless first == second
  rails.exec(["sh", "-c", "ruby app.rb > /fixture/server.log 2>&1"], detach: true)
  begin
    puts "Readiness: #{rails.host}:#{rails.mapped_port(3000)}/health"
    rails.wait_for_http(container_port: 3000, path: "/health", timeout: 30)
  rescue Testcontainers::TimeoutError
    execute!(rails, ["ruby", "-e", 'puts File.read("server.log"); require "net/http"; response = Net::HTTP.get_response(URI("http://127.0.0.1:3000/health")); puts response.code; puts response.body'])
    raise
  end

  client = FixtureContainer.new(ENV.fetch("CLIENT_IMAGE"))
    .with_env("API_URL" => "http://rails:3000")
    .with_labels("orpc-rails-suite" => run_id)
  containers << client
  client.start
  network.connect(client._id)
  client.store_file("/fixture/contract.ts", first)
  rpc_source = execute!(rails, ["ruby", "-r./app", "-e", 'print OrpcRails::RpcExporter.new(controller: "RpcFixtureController").generate'])
  client.store_file("/fixture/rpc-contract.ts", rpc_source)
  conformance = execute!(rails, ["ruby", "schema_conformance.rb"])
  client.store_file("/fixture/schema-conformance.ts", conformance)
  execute!(client, %w[npm run compatibility])
  execute!(client, %w[npm run rpc:compatibility])
  execute!(client, %w[npm test])
  puts "Packaged Rails/oRPC integration passed"
ensure
  containers.reverse_each do |container|
    container.remove(force: true, v: true)
  end
  network&.remove
  leftovers = Docker::Container.all(all: true,
    filters: MultiJson.dump(label: ["orpc-rails-suite=#{run_id}"]))
  raise "Suite containers leaked after teardown" unless leftovers.empty?
end
