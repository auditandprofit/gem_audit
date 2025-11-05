# frozen_string_literal: true

require_relative "../weightage"

module Gitlab
  module Dangerfiles
    module Weightage
      # Weights after (current multiplier of 2)
      #
      # +------------------------------+--------------------------------+
      # |        reviewer type         | weight(times in reviewer pool) |
      # +------------------------------+--------------------------------+
      # | reduced capacity reviewer    |                              1 |
      # | reviewer                     |                              2 |
      # | hungry reviewer              |                              4 |
      # | reduced capacity traintainer |                              1 |
      # | traintainer                  |                              2 |
      # | hungry traintainer           |                              6 |
      # +------------------------------+--------------------------------+
      #
      # @api private
      class Reviewers
        DEFAULT_REVIEWER_WEIGHT = Gitlab::Dangerfiles::Weightage::CAPACITY_MULTIPLIER * Gitlab::Dangerfiles::Weightage::BASE_REVIEWER_WEIGHT
        TRAINTAINER_WEIGHT = 2

        def initialize(reviewers, traintainers)
          @reviewers = reviewers
          @traintainers = traintainers
        end

        def execute
          # TODO: take CODEOWNERS into account?
          # https://gitlab.com/gitlab-org/gitlab/issues/26723

          remove_traintainers_from_reviewers!
          remove_maintainer_only_from_reviewers!

          weighted_reviewers + weighted_traintainers
        end

        private

        attr_reader :reviewers, :traintainers

        def remove_traintainers_from_reviewers!
          # Sometimes folks will add themselves as traintainers and not remove themselves as reviewers.
          # There seems no way currently to ensure only one of these entries exists for a person.
          # We need to protect ourselves from that scenario here as the code assumes a reviewer will only
          # appear in reviewers or traintainers, not both.
          reviewers.reject! { |reviewer| traintainers.include?(reviewer) }
        end

        def remove_maintainer_only_from_reviewers!
          # Using a maintainer-only reviewer emoji, team members can ensure they only get maintainer reviews
          reviewers.reject! { |reviewer| reviewer&.only_maintainer_reviews }
        end

        def weighted_reviewers
          reviewers.each_with_object([]) do |reviewer, total_reviewers|
            add_weighted_reviewer(total_reviewers, reviewer, DEFAULT_REVIEWER_WEIGHT)
          end
        end

        def weighted_traintainers
          traintainers.each_with_object([]) do |reviewer, total_traintainers|
            add_weighted_reviewer(total_traintainers, reviewer, DEFAULT_REVIEWER_WEIGHT + TRAINTAINER_WEIGHT)
          end
        end

        def add_weighted_reviewer(reviewers, reviewer, added_weight_for_hungry)
          if reviewer.reduced_capacity
            reviewers.fill(reviewer, reviewers.size, Gitlab::Dangerfiles::Weightage::BASE_REVIEWER_WEIGHT)
          elsif reviewer.hungry
            reviewers.fill(reviewer, reviewers.size, DEFAULT_REVIEWER_WEIGHT + added_weight_for_hungry)
          else
            reviewers.fill(reviewer, reviewers.size, DEFAULT_REVIEWER_WEIGHT)
          end
        end
      end
    end
  end
end
