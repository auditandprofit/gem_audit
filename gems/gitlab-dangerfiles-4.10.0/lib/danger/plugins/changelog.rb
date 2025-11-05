# frozen_string_literal: true

module Danger
  # Contains method to check the presense and validity of changelogs.
  class Changelog < Danger::Plugin
    NO_CHANGELOG_LABELS = [
      "maintenance::refactor",
      "maintenance::pipelines",
      "maintenance::workflow",
      "ci-build",
      "meta",
    ].freeze
    NO_CHANGELOG_CATEGORIES = %i[docs none].freeze
    CHANGELOG_TRAILER_REGEX = /^(?<name>Changelog):\s*(?<category>.+)$/i.freeze
    CHANGELOG_EE_TRAILER_REGEX = /^EE: true$/.freeze
    CHANGELOG_MODIFIED_URL_TEXT = "**CHANGELOG.md was edited.** Please remove the additions and follow the [changelog guidelines](https://docs.gitlab.com/ee/development/changelog.html).\n\n"
    CHANGELOG_MISSING_URL_TEXT = "**[CHANGELOG missing](https://docs.gitlab.com/ee/development/changelog.html)**:\n\n"
    IF_REVERT_MR_TEXT = <<~MARKDOWN
      In a revert merge request? Use the revert merge request template to add labels [that skip changelog checks](https://docs.gitlab.com/ee/development/pipelines#revert-mrs).

      Reverting something in the current milestone? A changelog isn't required. Skip changelog checks by adding `~"regression:*"` label, then re-run the danger job (there is a link at the bottom of this comment).
    MARKDOWN

    OPTIONAL_CHANGELOG_MESSAGE = {
      local: "If this merge request [doesn't need a CHANGELOG entry](https://docs.gitlab.com/ee/development/changelog.html#what-warrants-a-changelog-entry), feel free to ignore this message.",
      ci: <<~MSG
        If this merge request needs a changelog entry, add the `Changelog` trailer to the commit message you want to add to the changelog.

        If this merge request [doesn't need a CHANGELOG entry](https://docs.gitlab.com/ee/development/changelog.html#what-warrants-a-changelog-entry), feel free to ignore this message.
      MSG
    }.freeze
    SEE_DOC = "See the [changelog documentation](https://docs.gitlab.com/ee/development/changelog.html)."

    REQUIRED_CHANGELOG_REASONS = {
      db_changes: "introduces a database migration",
      feature_flag_removed: "removes a feature flag"
    }.freeze
    REQUIRED_CHANGELOG_MESSAGE = {
      local: "This merge request requires a changelog entry because it [%<reason>s](https://docs.gitlab.com/ee/development/changelog.html#what-warrants-a-changelog-entry).",
      ci: <<~MSG
        To create a changelog entry, add the `Changelog` trailer to one of your Git commit messages.

        This merge request requires a changelog entry because it [%<reason>s](https://docs.gitlab.com/ee/development/changelog.html#what-warrants-a-changelog-entry).
      MSG
    }.freeze
    DEFAULT_CHANGELOG_CATEGORIES = %w[
      added
      fixed
      changed
      deprecated
      removed
      security
      performance
      other
    ].freeze

    class ChangelogCheckResult
      attr_reader :errors, :warnings, :markdowns, :messages

      def initialize(errors: [], warnings: [], markdowns: [], messages: [])
        @errors = errors
        @warnings = warnings
        @markdowns = markdowns
        @messages = messages
      end

      private_class_method :new

      def self.empty
        new
      end

      def self.error(error)
        new(errors: [error])
      end

      def self.warning(warning)
        new(warnings: [warning])
      end

      def error(error)
        errors << error
      end

      def warning(warning)
        warnings << warning
      end

      def markdown(markdown)
        markdowns << markdown
      end

      def message(message)
        messages << message
      end
    end

    class CommitWrapper
      extend Forwardable

      attr_reader :category, :trailer_key

      def initialize(commit, trailer_key, category)
        @commit = commit
        @trailer_key = trailer_key
        @category = category
      end

      delegate %i[message sha] => :@commit
    end

    def categories
      valid_changelog_commits.map(&:category)
    end

    def check!
      return if revert_in_current_milestone?

      critical_checks
      regular_checks
      changelog_categories_checks
    end

    def revert_in_current_milestone?
      return false unless helper.revert_mr?
      # In dry-run mode, without the API token, we are able to fetch the current milestone nor the labels.
      # We simply assume that we are reverting in the current milestone.
      return true unless helper.ci?
      return false unless helper.current_milestone

      current_regression_label = "regression:#{helper.current_milestone.title}"

      helper.mr_labels.any?(current_regression_label)
    end

    def critical_checks
      check_result = ChangelogCheckResult.empty

      check_result.warning(modified_text) if git.modified_files.include?("CHANGELOG.md")

      # Help the user to apply the correct labels to skip this danger check in case it's a revert MR
      check_result.warning(IF_REVERT_MR_TEXT) if helper.revert_mr? && !helper.stable_branch?

      add_danger_messages(check_result)
    end

    def regular_checks
      if exist?
        add_danger_messages(check_changelog_path)
      elsif required?
        required_texts.each { |_, text| fail(text) } # rubocop:disable Lint/UnreachableLoop, Style/SignalException
      elsif optional?
        message optional_text
      end
    end

    def changelog_categories_checks
      check_changelog_commit_categories
    end

    # rubocop:disable Style/SignalException
    def add_danger_messages(check_result)
      check_result.errors.each { |error| fail(error) } # rubocop:disable Lint/UnreachableLoop
      check_result.warnings.each { |warning| warn(warning) }
      check_result.markdowns.each { |markdown_hash| markdown(**markdown_hash) }
      check_result.messages.each { |text| message(text) }
    end

    # rubocop:enable Style/SignalException

    def check_changelog_commit_categories
      changelog_commits.each do |commit|
        add_danger_messages(check_changelog_trailer(commit))
      end
    end

    def check_changelog_trailer(commit)
      unless commit.trailer_key == "Changelog"
        return ChangelogCheckResult.error("The changelog trailer for commit #{commit.sha} must be `Changelog` (starting with a capital C), not `#{commit.trailer_key}`")
      end

      return ChangelogCheckResult.empty if valid_categories.include?(commit.category)

      ChangelogCheckResult.error("Commit #{commit.sha} uses an invalid changelog category: #{commit.category}")
    end

    def check_changelog_path
      check_result = ChangelogCheckResult.empty
      return check_result unless exist?

      ee_changes = helper.changed_files(%r{\Aee/})

      if ee_changes.any? && !ee_changelog? && !required?
        check_result.warning("This MR changes code in `ee/`, but its Changelog commit is missing the [`EE: true` trailer](https://docs.gitlab.com/ee/development/changelog.html#gitlab-enterprise-changes). Consider adding it to your Changelog commits.")
      end

      if ee_changes.empty? && ee_changelog?
        check_result.warning("This MR has a Changelog commit for EE, but no code changes in `ee/`. Consider removing the `EE: true` trailer from your commits.")
      end

      if ee_changes.any? && ee_changelog? && required_reasons.include?(:db_changes)
        check_result.warning("This MR has a Changelog commit with the `EE: true` trailer, but there are database changes which [requires](https://docs.gitlab.com/ee/development/changelog.html#what-warrants-a-changelog-entry) the Changelog commit to not have the `EE: true` trailer. Consider removing the `EE: true` trailer from your commits.")
      end

      check_result
    end

    def required_reasons
      [].tap do |reasons|
        reasons << :db_changes if helper.changes.added.has_category?(:migration)
        reasons << :feature_flag_removed if helper.changes.deleted.has_category?(:feature_flag)
      end
    end

    def required?
      required_reasons.any?
    end

    def optional?
      categories_need_changelog? && mr_without_no_changelog_label?
    end

    def exist?
      valid_changelog_commits.any?
    end

    def changelog_commits
      git.commits.each_with_object([]) do |commit, memo|
        trailer = commit.message.match(CHANGELOG_TRAILER_REGEX)

        memo << CommitWrapper.new(commit, trailer[:name], trailer[:category]) if trailer
      end
    end

    def valid_changelog_commits
      changelog_commits.select do |commit|
        valid_categories.include?(commit.message.match(CHANGELOG_TRAILER_REGEX)[:category])
      end
    end

    def ee_changelog?
      changelog_commits.any? do |commit|
        commit.message.match?(CHANGELOG_EE_TRAILER_REGEX)
      end
    end

    def modified_text
      CHANGELOG_MODIFIED_URL_TEXT +
        (helper.ci? ? format(OPTIONAL_CHANGELOG_MESSAGE[:ci]) : OPTIONAL_CHANGELOG_MESSAGE[:local])
    end

    def required_texts
      required_reasons.each_with_object({}) do |required_reason, memo|
        memo[required_reason] =
          CHANGELOG_MISSING_URL_TEXT +
          format(REQUIRED_CHANGELOG_MESSAGE[helper.ci? ? :ci : :local], reason: REQUIRED_CHANGELOG_REASONS.fetch(required_reason))
      end
    end

    def optional_text
      CHANGELOG_MISSING_URL_TEXT +
        (helper.ci? ? format(OPTIONAL_CHANGELOG_MESSAGE[:ci]) : OPTIONAL_CHANGELOG_MESSAGE[:local])
    end

    private

    def changelog_config_file
      @changelog_config_file ||= File.join(helper.config.project_root, ".gitlab/changelog_config.yml")
    end

    def valid_categories
      return @categories if defined?(@categories)

      @categories = if File.exist?(changelog_config_file)
          begin
            YAML
              .load_file(changelog_config_file)
              .fetch("categories")
              .keys
              .freeze
          rescue Psych::SyntaxError, Psych::DisallowedClass => ex
            puts "#{changelog_config_file} doesn't seem to be a valid YAML file:\n#{ex.message}\nFallbacking to the default categories: #{DEFAULT_CHANGELOG_CATEGORIES}"
            DEFAULT_CHANGELOG_CATEGORIES
          rescue => ex
            puts "Received an unexpected failure while trying to fetch categories at #{changelog_config_file}:\n#{ex.message}\nFallbacking to the default categories: #{DEFAULT_CHANGELOG_CATEGORIES}"
            DEFAULT_CHANGELOG_CATEGORIES
          end
        else
          DEFAULT_CHANGELOG_CATEGORIES
        end
    end

    def read_file(path)
      File.read(path)
    end

    def categories_need_changelog?
      (helper.changes.categories - NO_CHANGELOG_CATEGORIES).any?
    end

    def mr_without_no_changelog_label?
      (helper.mr_labels & NO_CHANGELOG_LABELS).empty?
    end
  end
end
