# frozen_string_literal: true

module Labkit
  module CoveredExperience
    # Fakes Labkit::CoveredExperience::Experience.
    class Null
      include Singleton

      attr_reader :id, :description, :feature_category, :urgency

      def start(*_args)
        yield self if block_given?
        self
      end

      def push_attributes!(*_args) = self
      def checkpoint(*_args) = self
      def complete(*_args) = self
      def error!(*_args) = self
    end
  end
end
