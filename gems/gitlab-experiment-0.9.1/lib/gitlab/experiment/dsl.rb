# frozen_string_literal: true

module Gitlab
  class Experiment
    module Dsl
      def self.include_in(klass, with_helper: false)
        klass.include(self).tap { |base| base.helper_method(:experiment) if with_helper }
      end

      def experiment(name, variant_name = nil, **context, &block)
        raise ArgumentError, 'name is required' if name.nil?

        context[:request] ||= request if respond_to?(:request)

        base = Configuration.base_class.constantize
        klass = base.constantize(name) || base

        instance = klass.new(name, variant_name, **context, &block)
        return instance unless block

        instance.context.frozen? ? instance.run : instance.tap(&:run)
      end
    end
  end
end
