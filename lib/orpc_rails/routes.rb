# frozen_string_literal: true

module OrpcRails
  class Routes
    def initialize(routes)
      @routes = routes
    end

    def validate!(endpoint)
      candidates = @routes.routes.select do |route|
        route.path.spec.to_s.sub(/\(\.:format\)\z/, "") == endpoint.path &&
          route.verb.split("|").include?(endpoint.http_method)
      end
      route = candidates.first
      unless route && route.defaults[:controller] == endpoint.controller.controller_path &&
          route.defaults[:action] == endpoint.action &&
          endpoint.controller.action_methods.include?(endpoint.action)
        raise ArgumentError, "#{endpoint.key}: #{endpoint.http_method} #{endpoint.path} does not resolve to #{endpoint.controller.name}##{endpoint.action}"
      end

      extra_requirements = route.requirements.reject do |key, value|
        %i[controller action].include?(key) || (key == :format && value.to_s == "json")
      end
      unless extra_requirements.empty? && route.constraints.empty? &&
          route.app.is_a?(ActionDispatch::Routing::RouteSet::Dispatcher)
        raise ArgumentError, "#{endpoint.key}: constrained routes are not supported"
      end
      true
    end
  end
end
