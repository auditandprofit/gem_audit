# frozen_string_literal: true

require 'labkit/context'
require 'labkit/covered_experience/error'

module Labkit
  module CoveredExperience
    URGENCY_THRESHOLDS_IN_SECONDS = {
      sync_fast: 2,
      sync_slow: 5,
      async_fast: 15,
      async_slow: 300
    }.freeze

    # The `Experience` class represents a single Covered Experience
    # event to be measured and reported.
    class Experience
      attr_reader :error

      def initialize(definition)
        @definition = definition
      end

      # Start the Covered Experience.
      #
      # @yield [self] When a block is provided, the experience will be completed automatically.
      # @param extra [Hash] Additional data to include in the log event
      # @return [self]
      # @raise [CoveredExperienceError] If the block raises an error.
      #
      # Usage:
      #
      #  CoveredExperience.new(definition).start do |experience|
      #    experience.checkpoint
      #    experience.checkpoint
      #  end
      #
      #  experience = CoveredExperience.new(definition)
      #  experience.start
      #  experience.checkpoint
      #  experience.complete
      def start(**extra, &)
        @start_time = Time.now.utc
        checkpoint_counter.increment(checkpoint: "start")
        log_event("start", **extra)

        return self unless block_given?

        begin
          yield self
          self
        rescue StandardError => e
          error!(e)
          raise
        ensure
          complete(**extra)
        end
      end

      # Checkpoint the Covered Experience.
      #
      # @param extra [Hash] Additional data to include in the log event
      # @raise [UnstartedError] If the experience has not been started and RAILS_ENV is development or test.
      # @return [self]
      def checkpoint(**extra)
        return unless ensure_started!

        @checkpoint_time = Time.now.utc
        checkpoint_counter.increment(checkpoint: "intermediate")
        log_event("intermediate", **extra)

        self
      end

      # Complete the Covered Experience.
      #
      # @param extra [Hash] Additional data to include in the log event
      # @raise [UnstartedError] If the experience has not been started and RAILS_ENV is development or test.
      # @return [self]
      def complete(**extra)
        return unless ensure_started!

        begin
          @end_time = Time.now.utc
        ensure
          checkpoint_counter.increment(checkpoint: "end")
          total_counter.increment(error: has_error?)
          apdex_counter.increment(success: apdex_success?) unless has_error?
          log_event("end", **extra)
        end

        self
      end

      # Marks the experience as failed with an error
      #
      # @param error [StandardError, String] The error that caused the experience to fail.
      # @return [self]
      def error!(error)
        @error = error
        self
      end

      def has_error?
        !!@error
      end

      private

      def base_labels
        @base_labels ||= @definition.to_h.slice(:covered_experience, :feature_category, :urgency)
      end

      def ensure_started!
        return @start_time unless @start_time.nil?

        err = UnstartedError.new("Covered Experience #{@definition.covered_experience} not started")

        warn(err)
        raise(err) if %w[development test].include?(ENV['RAILS_ENV'])
      end

      def urgency_threshold
        URGENCY_THRESHOLDS_IN_SECONDS[@definition.urgency.to_sym]
      end

      def elapsed_time
        last_time = @end_time || @checkpoint_time || @start_time
        last_time - @start_time
      end

      def apdex_success?
        elapsed_time <= urgency_threshold
      end

      def checkpoint_counter
        @checkpoint_counter ||= Labkit::Metrics::Client.counter(
          :gitlab_covered_experience_checkpoint_total,
          'Total checkpoints for covered experiences',
          base_labels
        )
      end

      def total_counter
        @total_counter ||= Labkit::Metrics::Client.counter(
          :gitlab_covered_experience_total,
          'Total covered experience events (success/failure)',
          base_labels
        )
      end

      def apdex_counter
        @apdex_counter ||= Labkit::Metrics::Client.counter(
          :gitlab_covered_experience_apdex_total,
          'Total covered experience apdex events',
          base_labels
        )
      end

      def log_event(event_type, **extra)
        log_data = build_log_data(event_type, **extra)
        logger.info(log_data)
      end

      def build_log_data(event_type, **extra)
        log_data = {
          checkpoint: event_type,
          covered_experience: @definition.covered_experience,
          feature_category: @definition.feature_category,
          urgency: @definition.urgency,
          start_time: @start_time,
          checkpoint_time: @checkpoint_time,
          end_time: @end_time,
          elapsed_time_s: elapsed_time,
          urgency_threshold_s: urgency_threshold
        }
        log_data.merge!(extra) if extra

        if has_error?
          log_data[:error] = true
          log_data[:error_message] = @error.inspect
        end

        log_data.compact!

        log_data
      end

      def warn(exception)
        logger.warn(component: self.class.name, message: exception.message)
      end

      def logger
        Labkit::CoveredExperience.configuration.logger
      end
    end
  end
end
