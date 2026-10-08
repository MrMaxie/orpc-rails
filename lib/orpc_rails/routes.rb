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
      earlier = @routes.routes.take_while { |candidate| !candidate.equal?(route) }
      if earlier.any? { |candidate| method_matches?(candidate, endpoint.http_method) && overlaps?(candidate, endpoint.path) }
        raise ArgumentError, "#{endpoint.key}: an earlier Rails route may shadow #{endpoint.path}"
      end
      true
    end

    private

    def method_matches?(route, method)
      route.verb.empty? || route.verb.split("|").include?(method)
    end

    # Conservative overlap check: never execute request constraint predicates
    # or guess that one representative :id proves the entire path domain.
    def overlaps?(route, path)
      template = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
      flexible = template.include?("*") || template.include?("(")
      prefix = template.split(/[*(]/, 2).first
      prefix = prefix.sub(%r{[^/]+\z}, "") if flexible && !prefix.end_with?("/")
      left = prefix.split("/").reject(&:empty?)
      right = path.split("/").reject(&:empty?)
      return false if !flexible && left.size != right.size
      return false if flexible && left.size > right.size

      left.zip(right).all? do |a, b|
        a.include?(":") || b&.start_with?(":") || a == b
      end
    end
  end
end
