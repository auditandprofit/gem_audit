# frozen_string_literal: true

module Gitlab
  module Dangerfiles
    CapabilityStruct = Struct.new(:category, :project, :kind, :labels, keyword_init: true)

    class Capability < CapabilityStruct
      def self.for(category, **arguments)
        (category_to_class[category] || self)
          .new(category: category, **arguments)
      end

      def self.category_to_class
        @category_to_class ||= {
          none: None,
          test: Test,
          tooling: Tooling,
          import_integrate_be: ImportIntegrateBE,
          import_integrate_fe: ImportIntegrateFE,
          ux: UX
        }.freeze
      end
      private_class_method :category_to_class

      def has_capability?(teammate)
        teammate.capabilities(project).include?(capability)
      end

      private

      def capability
        @capability ||= "#{kind} #{category}"
      end

      class None < Capability
        def capability
          @capability ||= kind.to_s
        end
      end

      class Test < Capability
        def has_capability?(teammate)
          return false if kind != :reviewer

          area = teammate.role[/Software Engineer in Test(?:.*?, (\w+))/, 1]

          !!area && labels.any?("devops::#{area.downcase}")
        end
      end

      class Tooling < Capability
        def has_capability?(teammate)
          if super
            true
          elsif %i[trainee_maintainer maintainer].include?(kind)
            false
          else # fallback to backend reviewer
            teammate.capabilities(project).include?("#{kind} backend")
          end
        end
      end

      class ImportIntegrateBE < Capability
        def has_capability?(teammate)
          kind == :reviewer && teammate.role.match?(/Backend Engineer.+:Import and Integrate/)
        end
      end

      class ImportIntegrateFE < Capability
        def has_capability?(teammate)
          kind == :reviewer && teammate.role.match?(/Frontend Engineer.+:Import and Integrate/)
        end
      end

      class UX < Capability
        def has_capability?(teammate)
          super && teammate.member_of_the_group?(labels)
        end
      end
    end
  end
end
