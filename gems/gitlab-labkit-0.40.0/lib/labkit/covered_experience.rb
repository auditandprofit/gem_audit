# frozen_string_literal: true

require 'labkit/covered_experience/error'
require 'labkit/covered_experience/experience'
require 'labkit/covered_experience/null'
require 'labkit/covered_experience/registry'
require 'labkit/logging/json_logger'

module Labkit
  # Labkit::CoveredExperience namespace module.
  #
  # This module is responsible for managing covered experiences, which are
  # specific events or activities within the application that are measured
  # and reported for performance monitoring and analysis.
  module CoveredExperience
    # Configuration class for CoveredExperience
    class Configuration
      attr_accessor :logger

      def initialize
        @logger = Labkit::Logging::JsonLogger.new($stdout)
      end
    end

    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def reset_configuration
        @configuration = nil
      end

      def configure
        yield(configuration) if block_given?
      end

      def registry
        @registry ||= Registry.new
      end

      def reset
        @registry = nil
      end

      def get(experience_id)
        definition = registry[experience_id]

        if definition
          Experience.new(definition)
        else
          raise_or_null(experience_id)
        end
      end

      def start(experience_id, &)
        get(experience_id).start(&)
      end

      private

      def raise_or_null(experience_id)
        return Null.instance unless %w[development test].include?(ENV['RAILS_ENV'])

        raise(NotFoundError, "Covered Experience #{experience_id} not found in the registry")
      end
    end
  end
end
