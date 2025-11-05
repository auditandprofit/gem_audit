# frozen_string_literal: true

require "opentracing"

module Labkit
  module Tracing
    # https://edgeapi.rubyonrails.org/classes/ActiveSupport/Notifications/Instrumenter.html#method-c-new
    class AbstractInstrumenter
      def start(_name, _id, payload)
        scope = OpenTracing.start_active_span(span_name(payload))

        scope_stack.push scope
      end

      def finish(_name, _id, payload)
        scope = scope_stack.pop
        span = scope.span

        Labkit::Tracing::TracingUtils.log_common_fields_on_span(span, span_name(payload))

        # exception_object is the standard exception payload from ActiveSupport::Notifications
        # https://github.com/rails/rails/blob/v6.0.3.1/activesupport/lib/active_support/notifications/instrumenter.rb#L26
        exception = payload[:exception_object].presence || payload[:exception].presence
        Labkit::Tracing::TracingUtils.log_exception_on_span(span, exception)

        tags(payload).each do |k, v|
          span.set_tag(k, v)
        end

        scope.close
      end

      def scope_stack
        Thread.current[:_labkit_trace_scope_stack] ||= []
      end

      def span_name(_payload)
        raise "span_name not implemented"
      end

      def tags(_payload)
        {}
      end
    end
  end
end
