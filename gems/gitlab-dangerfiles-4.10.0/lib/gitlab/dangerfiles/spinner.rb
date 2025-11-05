# frozen_string_literal: true

require_relative "spin"
require_relative "teammate"
require_relative "weightage/maintainers"
require_relative "weightage/reviewers"

module Gitlab
  module Dangerfiles
    class Spinner
      attr_reader :project, :author, :team_author, :labels, :categories

      def initialize(
        project:, author:, team_author: nil, labels: [], categories: [],
        random: Random.new, ux_fallback_wider_community_reviewer: nil)
        @project = project
        @author = author
        @team_author = team_author
        @labels = labels
        @categories = categories.reject do |category|
          import_and_integrate_reject_category?(project, category, labels)
        end
        @random = random
        @ux_fallback_wider_community_reviewer = ux_fallback_wider_community_reviewer
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def spin
        spins = categories.sort_by(&:to_s).map do |category|
          spin_for_category(category)
        end

        backend_spin = spins.find { |spin| spin.category == :backend }
        frontend_spin = spins.find { |spin| spin.category == :frontend }

        spins.each do |spin|
          case spin.category
          when :qa
            spin.optional_role = :maintainer if
              categories.size > 1 && author_no_qa_capability?
          when :test
            spin.optional_role = :maintainer

            if spin.no_reviewer?
              # Fetch an already picked backend reviewer, or pick one otherwise
              spin.reviewer = backend_spin&.reviewer || spin_for_category(:backend).reviewer
            end
          when :tooling
            if spin.no_maintainer?
              # Fetch an already picked backend maintainer, or pick one otherwise
              spin.maintainer = backend_spin&.maintainer || spin_for_category(:backend).maintainer
            end
          when :ci_template # rubocop:disable Lint/DuplicateBranch -- bug?
            if spin.no_maintainer?
              # Fetch an already picked backend maintainer, or pick one otherwise
              spin.maintainer = backend_spin&.maintainer || spin_for_category(:backend).maintainer
            end
          when :analytics_instrumentation
            spin.optional_role = :maintainer

            if spin.no_maintainer?
              # Fetch an already picked maintainer, or pick one otherwise
              spin.maintainer = backend_spin&.maintainer || frontend_spin&.maintainer || spin_for_category(:backend).maintainer
            end
          when :import_integrate_be, :import_integrate_fe
            spin.optional_role = :maintainer
          when :ux
            spin.optional_role = :maintainer

            # We want at least a UX reviewer who can review any wider community
            # contribution even without a team designer. We assign this to Pedro.
            spin.reviewer = ux_fallback_wider_community_reviewer if
              labels.include?("Community contribution") &&
                spin.no_reviewer? &&
                spin.no_maintainer?
          end
        end

        spins
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Spin a reviewer for a particular approval rule
      #
      # @param [Hash] rule of approval
      #
      # @return [Gitlab::Dangerfiles::Teammate]
      def spin_for_approver(rule)
        approvers = rule["eligible_approvers"].filter_map do |approver|
          Gitlab::Dangerfiles::Teammate.find_member(
            approver["username"], project: project)
        end

        spin_for_person(approvers) || spin_for_approver_fallback(rule)
      end

      private

      attr_reader :random, :ux_fallback_wider_community_reviewer

      # Reject Import and Integrate categories if the MR author has reviewing abilities for the category.
      #
      # @param [String] category name
      # @return [Boolean]
      def import_and_integrate_reject_category?(project, category, labels)
        [:import_integrate_be, :import_integrate_fe].include?(category) && team_author &&
          (team_author.reviewer?(project, category, labels) || team_author.maintainer?(project, category, labels))
      end

      # MR includes QA changes, but also other changes, and author isn't an SET
      def author_no_qa_capability?
        !(team_author && team_author.capabilities(project).any? { |capability| capability.end_with?("qa") })
      end

      def spin_for_category(category)
        reviewers, traintainers, maintainers =
          %i[reviewer traintainer maintainer].map do |role|
            spin_role_for_category(role, category)
          end

        weighted_reviewers = Weightage::Reviewers.new(reviewers, traintainers).execute
        weighted_maintainers = Weightage::Maintainers.new(maintainers).execute

        reviewer = spin_for_person(weighted_reviewers)
        maintainer = spin_for_person(weighted_maintainers)

        # allow projects with small number of reviewers to take from maintainers if possible
        if reviewer.nil? && weighted_maintainers.uniq.size > 1
          weighted_maintainers.delete(maintainer)
          reviewer = spin_for_person(weighted_maintainers)
        end

        Spin.new(category, reviewer, maintainer, false)
      end

      def spin_role_for_category(role, category)
        team.select do |member|
          member.public_send(:"#{role}?", project, category, labels)
        end
      end

      # Known issue: If someone is rejected due to OOO, and then becomes not OOO, the
      # selection will change on next spin.
      #
      # @param [Array<Gitlab::Dangerfiles::Teammate>] people
      #
      # @return [Gitlab::Dangerfiles::Teammate]
      def spin_for_person(people)
        shuffled_people = people.shuffle(random: random)

        shuffled_people.find { |person| valid_person?(person) }
      end

      # @param [Gitlab::Dangerfiles::Teammate] person
      # @return [Boolean]
      def valid_person?(person)
        person.username != author && person.available
      end

      # It can be possible that we don't have a valid reviewer for approval.
      # In this case, we sample again without considering:
      #
      # * If they're available
      # * If they're an actual reviewer from roulette data
      #
      # We do this because we strictly require an approval from the approvers.
      #
      # @param [Hash] rule of approval
      #
      # @return [Gitlab::Dangerfiles::Teammate]
      def spin_for_approver_fallback(rule)
        fallback_approvers = rule["eligible_approvers"].map do |approver|
          Teammate.find_member(approver["username"]) || Teammate.new(approver)
        end

        # Intentionally not using `spin_for_person` to skip `valid_person?`.
        # This should strictly return someone so we don't filter anything,
        # and it's a fallback mechanism which should not happen often that
        # deserves a complex algorithm.
        fallback_approvers.sample(random: random)
      end

      # @return [Array<Gitlab::Dangerfiles::Teammate>]
      def team
        @team ||= Teammate.company_members.select do |member|
          member.in_project?(project)
        end
      end
    end
  end
end
