# frozen_string_literal: true

module Gitlab
  module Dangerfiles
    class Config
      # @!attribute project_root
      #   @return [String] the project root folder path.
      attr_accessor :project_root

      # @!attribute project_name
      #   @return [String] the project name. Currently used by the Roulette plugin to fetch relevant reviewers/maintainers based on the project name. Default to +ENV["CI_PROJECT_NAME"]+.
      attr_accessor :project_name

      # @!attribute ci_only_rules
      #   @return [Array<String>] rules that cannot be run locally.
      attr_accessor :ci_only_rules

      # @!attribute files_to_category
      #   @return [{Regexp => Array<Symbol>}, {Array<Regexp> => Array<Symbol>}] A hash of the form +{ filename_regex => categories, [filename_regex, changes_regex] => categories }+.
      #           +filename_regex+ is the regex pattern to match file names. +changes_regex+ is the regex pattern to
      #           match changed lines in files that match +filename_regex+. Used in `helper.changes_by_category`, `helper.changes`, and `helper.categories_for_file`.
      attr_accessor :files_to_category

      # @!attribute custom_labels_for_categories
      #   @return [{String => String}] A hash of the form +{ category_name => label }+.
      #           Used in `helper.custom_labels_for_categories`.
      attr_accessor :custom_labels_for_categories

      # @!attribute disabled_roulette_categories
      #   @return [Array] indicating which categories would be disabled for the simple roulette. Default to `[]` (all categories are enabled)
      attr_accessor :disabled_roulette_categories

      # Rule: changes_size
      # @!attribute code_size_thresholds
      #   @return [{ high: Integer, medium: Integer }] a hash of the form +{ high: 42, medium: 12 }+ where +:high+ is the lines changed threshold which triggers an error, and +:medium+ is the lines changed threshold which triggers a warning. Also, see +DEFAULT_CHANGES_SIZE_THRESHOLDS+ for the format of the hash.
      attr_accessor :code_size_thresholds

      # Rule: commit_messages
      # @!attribute max_commits_count
      #   @return [Integer] the maximum number of allowed non-squashed/non-fixup commits for a given MR. A warning is triggered if the MR has more commits.
      attr_accessor :max_commits_count

      # Rule: duo_code_review
      # @!attribute duo_code_review
      #   @return [Symbol] whether a review from GitLab Duo Code is `:mandatory` or `:optional`. Default to `:optional`.
      attr_accessor :duo_code_review

      # Rule: simple_roulette
      # @!attribute included_optional_codeowners_sections_for_roulette
      #   @return [Array] indicating which optional codeowners sections should be included in roulette. Default to `[]`.
      attr_accessor :included_optional_codeowners_sections_for_roulette

      # Rule: simple_roulette
      # @!attribute excluded_required_codeowners_sections_for_roulette
      #   @return [Array] indicating which required codeowners sections should be excluded from roulette. Default to `[]`.
      attr_accessor :excluded_required_codeowners_sections_for_roulette

      # @!attribute auto_assign_for_roulette_roles
      #   @return [Array<Symbol>] which roles to auto assign as reviewers, given roulette recommendations (:reviewer, :maintainer, or both). If empty, auto-assignment is disabled. Default to `[]`.
      attr_accessor :auto_assign_for_roulette_roles

      # @!attribute auto_assign_for_roulette_labels
      #   @return [Array<String>] MR labels that allow auto reviewer assignment. If empty, applies to all MRs, provided :auto_assign_for_roulette_roles is not empty. Default to `[]`.
      attr_accessor :auto_assign_for_roulette_labels

      DEFAULT_CHANGES_SIZE_THRESHOLDS = { high: 2_000, medium: 500 }.freeze
      DEFAULT_COMMIT_MESSAGES_MAX_COMMITS_COUNT = 10

      def initialize
        @files_to_category = {}
        @custom_labels_for_categories = {}
        @project_root = nil
        @project_name = ENV["CI_PROJECT_NAME"]
        @ci_only_rules = []
        @code_size_thresholds = DEFAULT_CHANGES_SIZE_THRESHOLDS
        @max_commits_count = DEFAULT_COMMIT_MESSAGES_MAX_COMMITS_COUNT
        @disabled_roulette_categories = []
        @included_optional_codeowners_sections_for_roulette = []
        @excluded_required_codeowners_sections_for_roulette = []
        @auto_assign_for_roulette_roles = []
        @auto_assign_for_roulette_labels = []
        @duo_code_review = :optional
      end
    end
  end
end
