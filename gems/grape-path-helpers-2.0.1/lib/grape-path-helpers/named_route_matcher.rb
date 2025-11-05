module GrapePathHelpers
  # methods to extend Grape::Endpoint so that calls
  # to unknown methods will look for a route with a matching
  # helper function name
  module NamedRouteMatcher
    def method_missing(method_name, *args)
      return super unless method_name.end_with?('_path')

      possible_routes = Grape::API::Instance
                        .decorated_routes_by_helper_name[method_name]
      return super unless possible_routes

      segments = args.first || {}
      return super unless segments.is_a?(Hash)

      requested_segments = segments.keys.map(&:to_s)

      route = possible_routes.detect do |r|
        r.uses_segments_in_path_helper?(requested_segments)
      end

      if route
        route.send(method_name, *args)
      else
        super
      end
    end
    ruby2_keywords(:method_missing)

    def respond_to_missing?(method_name, _include_private = false)
      grape_route_path?(method_name) || super
    end

    def grape_route_path?(method_name)
      method_name.end_with?('_path') &&
        !Grape::API::Instance
          .decorated_routes_by_helper_name[method_name].nil?
    end
  end
end
