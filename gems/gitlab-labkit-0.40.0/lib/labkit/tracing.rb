# frozen_string_literal: true

module Labkit
  # Tracing provides distributed tracing functionality
  module Tracing
    autoload :AbstractInstrumenter, "labkit/tracing/abstract_instrumenter"
    autoload :TracingCommon, "labkit/tracing/tracing_common"
    autoload :Factory, "labkit/tracing/factory"
    autoload :GRPC, "labkit/tracing/grpc"
    autoload :GRPCInterceptor, "labkit/tracing/grpc_interceptor" # Deprecated
    autoload :JaegerFactory, "labkit/tracing/jaeger_factory"
    autoload :RackMiddleware, "labkit/tracing/rack_middleware"
    autoload :Rails, "labkit/tracing/rails"
    autoload :Redis, "labkit/tracing/redis"
    autoload :ExternalHttp, "labkit/tracing/external_http"
    autoload :Sidekiq, "labkit/tracing/sidekiq"
    autoload :TracingUtils, "labkit/tracing/tracing_utils"

    # Tracing is only enabled when the `GITLAB_TRACING` env var is configured.
    def self.enabled?
      connection_string.present?
    end

    def self.connection_string
      ENV["GITLAB_TRACING"]
    end

    def self.tracing_url_template
      ENV["GITLAB_TRACING_URL"]
    end

    # Check if the current request is being traced.
    def self.sampled?
      context = OpenTracing.active_span&.context
      context&.respond_to?(:sampled?) && context&.sampled?
    end

    def self.stacktrace_operations
      @stacktrace_operations ||= Set.new(ENV["GITLAB_TRACING_INCLUDE_STACKTRACE"].to_s.split(",").map(&:strip))
    end

    def self.tracing_url_enabled?
      enabled? && tracing_url_template.present?
    end

    # This will provide a link into the distributed tracing for the current trace,
    # if it has been captured.
    def self.tracing_url(service_name)
      return unless tracing_url_enabled?

      correlation_id = Labkit::Correlation::CorrelationId.current_id.to_s

      # Avoid using `format` since it can throw TypeErrors
      # which we want to avoid on unsanitised env var input
      tracing_url_template.to_s
                          .gsub("{{ correlation_id }}", correlation_id)
                          .gsub("{{ service }}", service_name)
    end

    # This will run a block with a span
    # @param operation_name [String] The operation name for the span
    # @param tags [Hash] Tags to assign to the span
    # @param child_of [SpanContext, Span] SpanContext that acts as a parent to
    #  the newly-started span. If a span instance is provided, its
    #  context is automatically substituted.
    def self.with_tracing(**kwargs, &block)
      TracingUtils.with_tracing(**kwargs, &block)
    end
  end
end
