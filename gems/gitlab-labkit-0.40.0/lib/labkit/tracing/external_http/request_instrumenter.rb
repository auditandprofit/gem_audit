# frozen_string_literal: true

module Labkit
  module Tracing
    module ExternalHttp
      # For more information on the payloads: lib/labkit/net_http_publisher.rb
      class RequestInstrumenter < Labkit::Tracing::AbstractInstrumenter
        def span_name(_payload)
          "external_http:request"
        end

        def tags(payload)
          # Duration is calculated by start and end time
          # Exception is already captured in lib/labkit/tracing/tracing_utils.rb
          tags = {
            "component" => "external_http",
            "method" => payload[:method],
            "code" => payload[:code],
            "host" => payload[:host],
            "port" => payload[:port],
            "path" => payload[:path],
            "scheme" => payload[:scheme],
          }

          unless payload[:proxy_host].nil?
            tags["proxy_host"] = payload[:proxy_host]
            tags["proxy_port"] = payload[:proxy_port]
          end

          tags
        end
      end
    end
  end
end
