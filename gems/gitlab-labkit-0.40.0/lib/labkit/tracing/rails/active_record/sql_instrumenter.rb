# frozen_string_literal: true

module Labkit
  module Tracing
    module Rails
      module ActiveRecord
        # For more information on the payloads: https://guides.rubyonrails.org/active_support_instrumentation.html
        class SqlInstrumenter < Labkit::Tracing::AbstractInstrumenter
          OPERATION_NAME_PREFIX = "active_record:"
          DEFAULT_OPERATION_NAME = "sqlquery"

          def span_name(payload)
            OPERATION_NAME_PREFIX + (payload[:name].presence || DEFAULT_OPERATION_NAME)
          end

          def tags(payload)
            if Labkit::Tracing.sampled? && payload[:sql]
              sql = Labkit::Logging::Sanitizer.sanitize_sql(payload[:sql])
              fingerprint = Labkit::Logging::Sanitizer.sql_fingerprint(sql)
            end

            {
              "component" => COMPONENT_TAG,
              "span.kind" => "client",
              "db.type" => "sql",
              "db.connection_id" => payload[:connection_id],
              "db.cached" => payload[:cached] || false,
              "db.statement" => sql,
              "db.statement_fingerprint" => fingerprint,
            }
          end
        end
      end
    end
  end
end
