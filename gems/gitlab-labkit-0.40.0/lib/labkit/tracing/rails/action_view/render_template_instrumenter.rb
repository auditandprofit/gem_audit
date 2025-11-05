# frozen_string_literal: true

module Labkit
  module Tracing
    module Rails
      module ActionView
        # For more information on the payloads: https://guides.rubyonrails.org/active_support_instrumentation.html
        class RenderTemplateInstrumenter < Labkit::Tracing::AbstractInstrumenter
          def span_name(payload)
            identifier = ActionView.template_identifier(payload)
            if identifier.nil?
              "render_template"
            else
              "render_template:#{identifier}"
            end
          end

          def tags(payload)
            { "component" => COMPONENT_TAG, "template.id" => payload[:identifier], "template.layout" => payload[:layout] }
          end
        end
      end
    end
  end
end
