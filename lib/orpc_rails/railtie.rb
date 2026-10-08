# frozen_string_literal: true

require "rails"

module OrpcRails
  class Railtie < Rails::Railtie
    rake_tasks do
      namespace :orpc do
        desc "Export declared Rails endpoints to a TypeScript contract"
        task :export, [:path] => :environment do |_, args|
          raise ArgumentError, "Usage: rake 'orpc:export[path/to/contract.ts]'" unless args[:path]
          Rails.application.eager_load!
          Exporter.new(routes: Rails.application.routes).write(args[:path])
        end

        desc "Check the generated contract for drift without writing"
        task :check, [:path] => :environment do |_, args|
          raise ArgumentError, "Usage: rake 'orpc:check[path/to/contract.ts]'" unless args[:path]
          Rails.application.eager_load!
          Exporter.new(routes: Rails.application.routes).check(args[:path])
        end
      end
    end
  end
end
