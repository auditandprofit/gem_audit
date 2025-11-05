# frozen_string_literal: true

require "net/http"
require "json"

require_relative "../../../gitlab/dangerfiles/changes"
require_relative "../../../gitlab/dangerfiles/config"
require_relative "../../../gitlab/dangerfiles/teammate"
require_relative "../../../gitlab/dangerfiles/title_linting"

module Danger
  # Common helper functions for our danger scripts.
  class Helper < Danger::Plugin
    RELEASE_TOOLS_BOT = "gitlab-release-tools-bot"
    # rubocop:disable Style/HashSyntax
    CATEGORY_LABELS = {
      docs: "~documentation", # Docs are reviewed along DevOps stages, so don't need roulette for now.
      none: "None",
      nil => "N/A",
      qa: "~QA",
      ux: "~UX",
      codeowners: '~"Code Owners"',
      test: "~test for `spec/features/*`",
      tooling: '~"maintenance::workflow" for tooling, Danger, and RuboCop',
      pipeline: '~"maintenance::pipelines" for CI',
      ci_template: '~"ci::templates"',
      analytics_instrumentation: '~"analytics instrumentation"',
      import_integrate_be: '~"group::import and integrate" (backend)',
      import_integrate_fe: '~"group::import and integrate" (frontend)',
      Authentication: '~"group::authentication"',
      Authorization: '~"group::authorization"',
      Compliance: '~"group::compliance"',
      Verify: '~"devops::verify"',
      "AST:Composition Analysis": '~"group::composition analysis"',
      "AST:Dynamic Analysis": '~"group::dynamic analysis"',
      "AST:Secret Detection": '~"group::secret detection"',
      "AST:Static Analysis": '~"group::static analysis"'
    }.freeze
    # rubocop:enable Style/HashSyntax

    GITLAB_ORG_GROUP_ID = "9970"

    STABLE_BRANCH_REGEX = %r{\A(?<version>\d+-\d+)-stable-ee\z}

    # Allows to set specific rule's configuration by passing a block.
    #
    # @yield [c] Yield a Gitlab::Dangerfiles::Config object
    #
    # @yieldparam [Gitlab::Dangerfiles::Config] The Gitlab::Dangerfiles::Config object
    # @yieldreturn [Gitlab::Dangerfiles::Config] The Gitlab::Dangerfiles::Config object
    #
    # @example
    #   helper.config do |config|
    #     config.code_size_thresholds = { high: 42, medium: 12 }
    #   end
    #
    # @return [Gitlab::Dangerfiles::Config]
    def config
      (@config ||= Gitlab::Dangerfiles::Config.new).tap do |c|
        yield c if block_given?
      end
    end

    # @example
    #   <a href='https://gitlab.com/artsy/eigen/blob/561827e46167077b5e53515b4b7349b8ae04610b/file.txt'>file.txt</a>
    #
    # @param [String,  Array<String>] paths
    #        A list of strings to convert to gitlab anchors
    # @param [Boolean] full_path
    #        Shows the full path as the link's text, defaults to +true+.
    #
    # @see https://danger.systems/reference.html Danger reference where #html_link is described
    # @see https://github.com/danger/danger/blob/eca19719d3e585fe1cc46bc5377f9aa955ebf609/lib/danger/danger_core/plugins/dangerfile_gitlab_plugin.rb#L216 Danger reference where #html_link is implemented
    #
    # @return [String] a list of HTML anchors for a file, or multiple files
    def html_link(paths, full_path: true)
      ci? ? gitlab_helper.html_link(paths, full_path: full_path) : paths
    end

    # @return [Boolean] whether we're in the CI context or not.
    def ci?
      !gitlab_helper.nil?
    end

    # @return [Array<String>] a list of filenames added in this MR.
    def added_files
      @added_files ||= if changes_from_api
          changes_from_api.select { |file| file["new_file"] }.map { |file| file["new_path"] }
        else
          git.added_files.to_a
        end
    end

    # @return [Array<String>] a list of filenames modifier in this MR.
    def modified_files
      @modified_files ||= if changes_from_api
          changes_from_api.select { |file| !file["new_file"] && !file["deleted_file"] && !file["renamed_file"] }.map { |file| file["new_path"] }
        else
          git.modified_files.to_a
        end
    end

    # @return [Array<String>] a list of filenames renamed in this MR.
    def renamed_files
      @renamed_files ||= if changes_from_api
          changes_from_api.select { |file| file["renamed_file"] }.each_with_object([]) do |file, memo|
            memo << { before: file["old_path"], after: file["new_path"] }
          end
        else
          git.renamed_files.to_a
        end
    end

    # @return [Array<String>] a list of filenames deleted in this MR.
    def deleted_files
      @deleted_files ||= if changes_from_api
          changes_from_api.select { |file| file["deleted_file"] }.map { |file| file["new_path"] }
        else
          git.deleted_files.to_a
        end
    end

    # @example
    #   # Considering these changes:
    #   # - A new_file.rb
    #   # - D deleted_file.rb
    #   # - M modified_file.rb
    #   # - R renamed_file_before.rb -> renamed_file_after.rb
    #   # it will return:
    #
    #   #=> ['new_file.rb', 'modified_file.rb', 'renamed_file_after.rb']
    #
    #
    # @return [Array<String>] a list of all files that have been added, modified or renamed.
    #   +modified_files+ might contain paths that already have been renamed,
    #   so we need to remove them from the list.
    def all_changed_files
      changes.files - changes.deleted.files - changes.renamed_before.files
    end

    # @param filename [String] A file name for which we want the diff.
    #
    # @example
    #   # Considering changing a line in lib/gitlab/usage_data.rb, it will return:
    #
    #   ["--- a/lib/gitlab/usage_data.rb",
    #    "+++ b/lib/gitlab/usage_data.rb",
    #    "+      # Test change",
    #    "-      # Old change"]
    #
    # @return [Array<String>] an array of changed lines in Git diff format.
    def changed_lines(filename)
      diff = diff_for_file(filename)
      return [] unless diff

      diff.split("\n").select { |line| %r{^[+-]}.match?(line) }
    end

    def release_automation?
      mr_author == RELEASE_TOOLS_BOT
    end

    # @param items [Array<String>] An array of items to transform into a bullet list.
    #
    # @example
    #   markdown_list(%w[foo bar])
    #   # => * foo
    #        * bar
    #
    # @return [String] a bullet list for the given +items+. If there are more than 10 items, wrap the list in a +<details></details>+ block.
    def markdown_list(items)
      list = items.map { |item| "* `#{item}`" }.join("\n")

      if items.size > 10
        "\n<details>\n\n#{list}\n\n</details>\n"
      else
        list
      end
    end

    # @param categories [{Regexp => Array<Symbol>}, {Array<Regexp> => Array<Symbol>}] A hash of the form +{ filename_regex => categories, [filename_regex, changes_regex] => categories }+.
    #                   +filename_regex+ is the regex pattern to match file names. +changes_regex+ is the regex pattern to
    #                   match changed lines in files that match +filename_regex+
    #
    # @return [{Symbol => Array<String>}] a hash of the type +{ category1: ["file1", "file2"], category2: ["file3", "file4"] }+
    #   using filename regex (+filename_regex+) and specific change regex (+changes_regex+) from the given +categories+ hash.
    def changes_by_category(categories = [])
      changed_and_deleted_files = all_changed_files + changes.deleted.files

      changed_and_deleted_files.each_with_object(Hash.new { |h, k| h[k] = [] }) do |file, hash|
        categories_for_file(file, categories).each { |category| hash[category] << file }
      end
    end

    # @param categories [{Regexp => Array<Symbol>}, {Array<Regexp> => Array<Symbol>}] A hash of the form +{ filename_regex => categories, [filename_regex, changes_regex] => categories }+.
    #                   +filename_regex+ is the regex pattern to match file names. +changes_regex+ is the regex pattern to
    #                   match changed lines in files that match +filename_regex+
    #
    # @return [Gitlab::Dangerfiles::Changes] a +Gitlab::Dangerfiles::Changes+ object that represents the changes of an MR
    #   using filename regex (+filename_regex+) and specific change regex (+changes_regex+) from the given +categories+ hash.
    def changes(categories = [])
      Gitlab::Dangerfiles::Changes.new([]).tap do |changes|
        added_files.each do |file|
          categories_for_file(file, categories).each { |category| changes << Gitlab::Dangerfiles::Change.new(file, :added, category) }
        end

        modified_files.each do |file|
          categories_for_file(file, categories).each { |category| changes << Gitlab::Dangerfiles::Change.new(file, :modified, category) }
        end

        deleted_files.each do |file|
          categories_for_file(file, categories).each { |category| changes << Gitlab::Dangerfiles::Change.new(file, :deleted, category) }
        end

        renamed_files.map { |x| x[:before] }.each do |file|
          categories_for_file(file, categories).each { |category| changes << Gitlab::Dangerfiles::Change.new(file, :renamed_before, category) }
        end

        renamed_files.map { |x| x[:after] }.each do |file|
          categories_for_file(file, categories).each { |category| changes << Gitlab::Dangerfiles::Change.new(file, :renamed_after, category) }
        end
      end
    end

    # @param filename [String] A file name.
    # @param files_to_category [{Regexp => Array<Symbol>}, {Array<Regexp> => Array<Symbol>}] A hash of the form +{ filename_regex => categories, [filename_regex, changes_regex] => categories }+.
    #                          +filename_regex+ is the regex pattern to match file names. +changes_regex+ is the regex pattern to
    #                          match changed lines in files that match +filename_regex+
    #
    # @return [Array<Symbol>] the categories a file is in, e.g., +[:frontend]+, +[:backend]+, or +%i[frontend tooling]+
    #   using filename regex (+filename_regex+) and specific change regex (+changes_regex+) from the given +categories+ hash.
    def categories_for_file(filename, files_to_category = {})
      files_to_category = Array(files_to_category).compact
      files_to_category = helper.config.files_to_category if files_to_category.empty?

      _, categories = files_to_category.find do |key, _|
        filename_regex, changes_regex = Array(key)

        found = filename_regex.match?(filename)
        found &&= changed_lines(filename).any? { |changed_line| changes_regex.match?(changed_line) } if changes_regex

        found
      end

      Array(categories || :none)
    end

    # @param category [Symbol] A category.
    #
    # @return [String] the GFM for a category label, making its best guess if it's not
    #   a category we know about.
    def label_for_category(category)
      helper.config.custom_labels_for_categories[category] || CATEGORY_LABELS[category] ||

        if category.start_with?("`")
          category.to_s
        else
          %Q{~"#{category}"}
        end
    end

    # @return [String] +""+ when not in the CI context, and the MR Source Project ID as a string otherwise.
    def mr_source_project_id
      return "" unless ci?

      gitlab_helper.mr_json["source_project_id"].to_s
    end

    # @return [String] +""+ when not in the CI context, and the MR Target Project ID as a string otherwise.
    def mr_target_project_id
      return "" unless ci?

      gitlab_helper.mr_json["target_project_id"].to_s
    end

    # @return [String] +""+ when not in the CI context, and the MR IID as a string otherwise.
    def mr_iid
      return "" unless ci?

      gitlab_helper.mr_json["iid"].to_s
    end

    # @return [String] +`whoami`+ when not in the CI context, and the MR author username otherwise.
    def mr_author
      return `whoami`.strip unless ci?

      gitlab_helper.mr_author
    end

    # @return [Array<Hash>] +[]+ when not in the CI context, and the MR assignees otherwise.
    def mr_assignees
      return [] unless ci?

      gitlab_helper.mr_json["assignees"]
    end

    # @return [Array<Hash>] +[]+ when not in the CI context, and the MR reviewers otherwise.
    def mr_reviewers
      return [] unless ci?

      gitlab_helper.mr_json["reviewers"]
    end

    # @return [String] +""+ when not in the CI context, and the MR title otherwise.
    def mr_title
      return "" unless ci?

      gitlab_helper.mr_json["title"]
    end

    # @return [String] +""+ when not in the CI context, and the MR description otherwise.
    def mr_description
      return "" unless ci?

      gitlab_helper.mr_body
    end

    # @return [String] +""+ when not in the CI context, and the MR URL otherwise.
    def mr_web_url
      return "" unless ci?

      gitlab_helper.mr_json["web_url"]
    end

    # @return [Hash, nil] +nil+ when not in the CI context, and the MR milestone otherwise.
    def mr_milestone
      return unless ci?

      gitlab_helper.mr_json["milestone"]
    end

    # @return [Array<String>] +[]+ when not in the CI context, and the MR labels otherwise.
    def mr_labels
      return [] unless ci?

      (gitlab_helper.mr_labels + labels_to_add).uniq
    end

    # @return [String] +`git rev-parse --abbrev-ref HEAD`+ when not in the CI context, and the MR source branch otherwise.
    def mr_source_branch
      return `git rev-parse --abbrev-ref HEAD`.strip unless ci?

      gitlab_helper.mr_json["source_branch"]
    end

    # @return [String] +""+ when not in the CI context, and the MR target branch otherwise.
    def mr_target_branch
      return "" unless ci?

      gitlab_helper.mr_json["target_branch"]
    end

    # @return [Hash] +{}+ when not in the CI context, and the merge request approval state otherwise.
    def mr_approval_state
      return {} unless ci?

      gitlab_helper.api.merge_request_approval_state(
        mr_target_project_id, mr_iid
      )
    end

    MR_REVERT_START_WITH = /[Rr]evert /

    # When API token is available matches MR title to start with "Revert " or "revert ".
    # Otherwise, matches if the single commit's message starts with "Revert " or "revert ".
    #
    # @return [Boolean] whether an MR is a revert
    def revert_mr?
      if ci?
        mr_title.start_with?(MR_REVERT_START_WITH)
      else
        git.commits.size == 1 && git.commits.first.message.start_with?(MR_REVERT_START_WITH)
      end
    end

    # @return [Boolean] +true+ when not in the CI context, and whether the MR is set to be squashed otherwise.
    def squash_mr?
      return true unless ci?

      gitlab.mr_json["squash"]
    end

    # @return [Boolean] whether a MR is a Draft or not.
    def draft_mr?
      return false unless ci?

      gitlab.mr_json["work_in_progress"]
    end

    # @return [Boolean] whether a MR is opened in the security mirror or not.
    def security_mr?
      mr_web_url.include?("/gitlab-org/security/")
    end

    def stable_branch_mr?
      !!mr_target_branch.match(STABLE_BRANCH_REGEX) && !security_mr?
    end

    # @return [Boolean] whether a MR title includes "cherry-pick" or not.
    def cherry_pick_mr?
      Gitlab::Dangerfiles::TitleLinting.has_cherry_pick_flag?(mr_title)
    end

    # @return [Boolean] whether a MR title includes "RUN ALL RSPEC" or not.
    def run_all_rspec_mr?
      Gitlab::Dangerfiles::TitleLinting.has_run_all_rspec_flag?(mr_title)
    end

    # @return [Boolean] whether a MR title includes "RUN AS-IF-FOSS" or not.
    def run_as_if_foss_mr?
      Gitlab::Dangerfiles::TitleLinting.has_run_as_if_foss_flag?(mr_title)
    end

    # @return [Boolean] whether a MR targets a stable branch or not.
    def stable_branch?
      /\A\d+-\d+-stable-ee/i.match?(mr_target_branch)
    end

    # Whether a MR has a scoped label with the given scope set or not.
    #
    # @param scope [String] The scope for which to look for labels, e.g. +type+ would look for any +type::*+ label.
    #
    # @return [Boolean]
    def has_scoped_label_with_scope?(scope)
      mr_labels.any? { |label| label.start_with?("#{scope}::") }
    end

    # @return [Boolean] whether a MR has any CI-related changes (i.e. +".gitlab-ci.yml"+ or +".gitlab/ci/*"+) or not.
    def has_ci_changes?
      changed_files(%r{\A(\.gitlab-ci\.yml|\.gitlab/ci/)}).any?
    end

    # @param labels [Array<String>] An array of labels.
    #
    # @return [Boolean] whether a MR has the given +labels+ set or not.
    def mr_has_labels?(*labels)
      labels = labels.flatten.uniq

      (labels & mr_labels) == labels
    end

    # @param labels [Array<String>] An array of labels.
    # @param sep [String] A separator.
    #
    # @example
    #   labels_list(["foo", "bar baz"], sep: "; ")
    #    # => '~"foo"; ~"bar baz"'
    #
    # @return [String] the list of +labels+ ready for being used in a Markdown comment, separated by +sep+.
    def labels_list(labels, sep: ", ")
      labels.map { |label| %Q{~"#{label}"} }.join(sep)
    end

    # @deprecated Use {#quick_action_label} instead.
    def prepare_labels_for_mr(labels)
      quick_action_label(labels)
    end

    # @param labels [Array<String>] An array of labels.
    #
    # @example
    #   quick_action_label(["foo", "bar baz"])
    #    # => '/label ~"foo" ~"bar baz"'
    #
    # @return [String] a quick action to set the +given+ labels. Returns +""+ if +labels+ is empty.
    def quick_action_label(labels)
      return "" unless labels.any?

      "/label #{labels_list(labels, sep: " ")}"
    end

    # @param regex [Regexp] A Regexp to match against.
    #
    # @return [Array<String>] changed files matching the given +regex+.
    def changed_files(regex)
      all_changed_files.grep(regex)
    end

    # @return [String] the group label (i.e. +"group::*"+) set on the MR.
    def group_label
      mr_labels.find { |label| label.start_with?("group::") }
    end

    # @return [String] the stage label (i.e. +"devops::*"+) set on the MR.
    def stage_label
      mr_labels.find { |label| label.start_with?("devops::") }
    end

    # Accessor for storing labels to add so that other rules can check if labels will be added after Danger
    # has evaluated all the rules.
    # For instance, a rule might require a specific label to be set, but another rule could add this label
    # itself. Without this method, the first rule wouldn't know that the label would be applied and would ask
    # for it anyway.
    #
    # @return [Array<String>] the list of labels that Danger will add
    def labels_to_add
      @labels_to_add ||= []
    end

    # @return [Hash] the current API milestone object or +nil+ if run in dry-run mode
    def current_milestone
      return unless ci?

      @current_milestone ||= gitlab_helper.api.group_milestones(GITLAB_ORG_GROUP_ID, state: "active")
        .auto_paginate
        .select { |m| m.title.match?(/\A\d+\.\d+\z/) && !m.expired && m.start_date && m.due_date }
        .min_by(&:start_date)
    end

    private

    # @return [Danger::RequestSources::GitLab, nil] the +gitlab+ helper, or +nil+ when it's not available.
    def gitlab_helper
      # Unfortunately the following does not work:
      # - respond_to?(:gitlab)
      # - respond_to?(:gitlab, true)
      gitlab
    rescue NoMethodError
      nil
    end

    # @param filename [String] A filename for which we want the diff.
    #
    # @return [String] the raw diff as a string for the given +filename+.
    def diff_for_file(filename)
      if changes_from_api
        changes_hash = changes_from_api.find { |file| file["new_path"] == filename }
        changes_hash["diff"] if changes_hash
      else
        git.diff_for_file(filename)&.patch
      end
    end

    # Fetches MR changes from the API instead of Git (default).
    #
    # @return [Array<Hash>, nil]
    def changes_from_api
      return nil unless ci?
      return nil if defined?(@force_changes_from_git)

      @changes_from_api ||= gitlab_helper.mr_changes
    rescue
      # Fallback to the Git strategy in any case
      @force_changes_from_git = true
      nil
    end
  end
end
