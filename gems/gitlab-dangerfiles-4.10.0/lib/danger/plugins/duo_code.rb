# frozen_string_literal: true

module Danger
  # Contains method to check if Duo code suggestion added to MR as a reviewer.
  class DuoCode < Danger::Plugin
    def suggestion_added?
      return false unless helper.ci?

      helper.mr_reviewers.include?("GitLabDuo")
    end
  end
end
