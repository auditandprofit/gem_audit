# frozen_string_literal: true

require "action_dispatch"
require "json"

module Labkit
  module Middleware
    HEADER = "X-Gitlab-Meta"

    # This is a rack middleware to be inserted in GitLab-rails
    # It makes sure that there's always a root context containing the correlation
    # id.
    # Since this context always get's cleaned up by this middleware, we can be
    # sure that any nested contexts will also be cleaned up.
    class Rack
      def initialize(app)
        @app = app
      end

      def call(env)
        Labkit::Context.with_context(Labkit::Context::CORRELATION_ID_KEY => correlation_id(env)) do |context|
          status, headers, response = @app.call(env)

          headers[HEADER] = context_to_json(context)

          [status, headers, response]
        end
      end

      private

      def correlation_id(env)
        request(env).request_id
      end

      def request(env)
        ActionDispatch::Request.new(env)
      end

      def context_to_json(context)
        context
          .to_h
          .transform_keys { |k| k.delete_prefix("meta.") }
          .merge("version" => "1")
          .to_json
      end
    end
  end
end
