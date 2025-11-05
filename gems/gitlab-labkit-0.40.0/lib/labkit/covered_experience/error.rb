# frozen_string_literal: true

module Labkit
  module CoveredExperience
    CoveredExperienceError = Class.new(StandardError)
    UnstartedError = Class.new(CoveredExperienceError)
    NotFoundError = Class.new(CoveredExperienceError)
  end
end
