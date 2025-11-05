# frozen_string_literal: true

require_relative "../weightage"

module Gitlab
  module Dangerfiles
    module Weightage
      # @api private
      class Maintainers
        def initialize(maintainers)
          @maintainers = maintainers
        end

        def execute
          maintainers.each_with_object([]) do |maintainer, weighted_maintainers|
            add_weighted_reviewer(weighted_maintainers, maintainer, Gitlab::Dangerfiles::Weightage::BASE_REVIEWER_WEIGHT)
          end
        end

        private

        attr_reader :maintainers

        def add_weighted_reviewer(reviewers, reviewer, weight)
          if reviewer.reduced_capacity
            reviewers.fill(reviewer, reviewers.size, weight)
          else
            reviewers.fill(reviewer, reviewers.size, weight * Gitlab::Dangerfiles::Weightage::CAPACITY_MULTIPLIER)
          end
        end
      end
    end
  end
end
