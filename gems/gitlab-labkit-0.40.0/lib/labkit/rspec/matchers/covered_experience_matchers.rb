# frozen_string_literal: true

# RSpec matchers for testing Labkit CoveredExperience functionality
#
# This file must be explicitly required in your test setup:
#   require 'labkit/rspec/matchers'

raise LoadError, "RSpec is not loaded. Please require 'rspec' before requiring 'labkit/rspec/matchers'" unless defined?(RSpec)

module Labkit
  module RSpec
    module Matchers
      # Helper module for CoveredExperience functionality
      module CoveredExperience
        def attributes(covered_experience_id)
          raise ArgumentError, "covered_experience_id is required" if covered_experience_id.nil?

          definition = Labkit::CoveredExperience::Registry.new[covered_experience_id]
          definition.to_h.slice(:covered_experience, :feature_category, :urgency)
        end

        def checkpoint_counter
          Labkit::Metrics::Client.get(:gitlab_covered_experience_checkpoint_total)
        end

        def total_counter
          Labkit::Metrics::Client.get(:gitlab_covered_experience_total)
        end

        def apdex_counter
          Labkit::Metrics::Client.get(:gitlab_covered_experience_apdex_total)
        end
      end
    end
  end
end

# Matcher for verifying CoveredExperience start metrics instrumentation.
#
# Usage:
#   expect { subject }.to start_covered_experience('rails_request')
#
# This matcher verifies that the following metric is incremented:
# - gitlab_covered_experience_checkpoint_total (with checkpoint=start)
#
# Parameters:
# - covered_experience_id: Required. The ID of the covered experience (e.g., 'rails_request')
RSpec::Matchers.define :start_covered_experience do |covered_experience_id|
  include Labkit::RSpec::Matchers::CoveredExperience

  description { "start covered experience '#{covered_experience_id}'" }
  supports_block_expectations

  match do |actual|
    labels = attributes(covered_experience_id)

    checkpoint_before = checkpoint_counter&.get(labels.merge(checkpoint: "start")).to_i

    actual.call

    checkpoint_after = checkpoint_counter&.get(labels.merge(checkpoint: "start")).to_i

    @checkpoint_change = checkpoint_after - checkpoint_before

    @checkpoint_change == 1
  end

  failure_message do
    "Failed to checkpoint covered experience '#{covered_experience_id}':\n" \
      "expected checkpoint='start' counter to increase by 1, but increased by #{@checkpoint_change}"
  end
end

# Matcher for verifying CoveredExperience checkpoint metrics instrumentation.
#
# Usage:
#   expect { subject }.to checkpoint_covered_experience('rails_request')
#
# This matcher verifies that the following metric is incremented:
# - gitlab_covered_experience_checkpoint_total (with checkpoint=intermediate)
#
# Parameters:
# - covered_experience_id: Required. The ID of the covered experience (e.g., 'rails_request')
RSpec::Matchers.define :checkpoint_covered_experience do |covered_experience_id|
  include Labkit::RSpec::Matchers::CoveredExperience

  description { "checkpoint covered experience '#{covered_experience_id}'" }
  supports_block_expectations

  match do |actual|
    labels = attributes(covered_experience_id)

    checkpoint_before = checkpoint_counter&.get(labels.merge(checkpoint: "intermediate")).to_i

    actual.call

    checkpoint_after = checkpoint_counter&.get(labels.merge(checkpoint: "intermediate")).to_i
    @checkpoint_change = checkpoint_after - checkpoint_before

    @checkpoint_change == 1
  end

  failure_message do
    "Failed to checkpoint covered experience '#{covered_experience_id}':\n" \
      "expected checkpoint='intermediate' counter to increase by 1, but increased by #{@checkpoint_change}"
  end

  match_when_negated do |actual|
    labels = attributes(covered_experience_id)

    checkpoint_before = checkpoint_counter&.get(labels.merge(checkpoint: "intermediate")).to_i

    actual.call

    checkpoint_after = checkpoint_counter&.get(labels.merge(checkpoint: "intermediate")).to_i
    @checkpoint_change = checkpoint_after - checkpoint_before

    @checkpoint_change.zero?
  end

  failure_message_when_negated do
    "Expected covered experience '#{covered_experience_id}' NOT to checkpoint:\n" \
      "expected checkpoint='intermediate' counter to increase by 0, but increased by #{@checkpoint_change}"
  end
end

# Matcher for verifying CoveredExperience completion metrics instrumentation.
#
# Usage:
#   expect { subject }.to complete_covered_experience('rails_request')
#
# This matcher verifies that the following metrics are incremented with specific labels:
# - gitlab_covered_experience_checkpoint_total (with checkpoint=end)
# - gitlab_covered_experience_total (with error=false)
# - gitlab_covered_experience_apdex_total (with success=true)
#
# Parameters:
# - covered_experience_id: Required. The ID of the covered experience (e.g., 'rails_request')
# - error: Optional. The expected error flag for gitlab_covered_experience_total (false by default)
# - success: Optional. The expected success flag for gitlab_covered_experience_apdex_total (true by default)
RSpec::Matchers.define :complete_covered_experience do |covered_experience_id, error: false, success: true|
  include Labkit::RSpec::Matchers::CoveredExperience

  description { "complete covered experience '#{covered_experience_id}'" }
  supports_block_expectations

  match do |actual|
    labels = attributes(covered_experience_id)

    checkpoint_before = checkpoint_counter&.get(labels.merge(checkpoint: "end")).to_i
    total_before = total_counter&.get(labels.merge(error: error)).to_i
    apdex_before = apdex_counter&.get(labels.merge(success: success)).to_i

    actual.call

    checkpoint_after = checkpoint_counter&.get(labels.merge(checkpoint: "end")).to_i
    total_after = total_counter&.get(labels.merge(error: error)).to_i
    apdex_after = apdex_counter&.get(labels.merge(success: success)).to_i
    @checkpoint_change = checkpoint_after - checkpoint_before
    @total_change = total_after - total_before
    @apdex_change = apdex_after - apdex_before

    @checkpoint_change == 1 && @total_change == 1 && @apdex_change == (error ? 0 : 1)
  end

  failure_message do
    "Failed to complete covered experience '#{covered_experience_id}':\n" \
      "expected checkpoint='end' counter to increase by 1, but increased by #{@checkpoint_change}\n" \
      "expected total='error: #{error}' counter to increase by 1, but increased by #{@total_change}\n" \
      "expected apdex='success: #{success}' counter to increase by 1, but increased by #{@apdex_change}"
  end

  match_when_negated do |actual|
    labels = attributes(covered_experience_id)

    checkpoint_before = checkpoint_counter&.get(labels.merge(checkpoint: "end")).to_i
    total_before = total_counter&.get(labels.merge(error: error)).to_i
    apdex_before = apdex_counter&.get(labels.merge(success: success)).to_i

    actual.call

    checkpoint_after = checkpoint_counter&.get(labels.merge(checkpoint: "end")).to_i
    total_after = total_counter&.get(labels.merge(error: error)).to_i
    apdex_after = apdex_counter&.get(labels.merge(success: success)).to_i
    @checkpoint_change = checkpoint_after - checkpoint_before
    @total_change = total_after - total_before
    @apdex_change = apdex_after - apdex_before

    @checkpoint_change.zero? && @total_change.zero? && @apdex_change == (error ? 1 : 0)
  end

  failure_message_when_negated do
    "Failed covered experience '#{covered_experience_id}' NOT to complete:\n" \
      "expected checkpoint='end' counter to increase by 0, but increased by #{@checkpoint_change}\n" \
      "expected total='error: #{error}' counter to increase by 0, but increased by #{@total_change}\n" \
      "expected apdex='success: #{success}' counter to increase by 0, but increased by #{@apdex_change}"
  end
end
