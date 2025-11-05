# frozen_string_literal: true

# The random rollout strategy will randomly assign a variant when the context is determined to be within the experiment
# group.
#
# If caching is enabled this is a predicable and consistent assignment that will eventually assign a variant (since
# control isn't cached) but if caching isn't enabled, assignment will be random each time.
#
# Example configuration usage:
#
# config.default_rollout = Gitlab::Experiment::Rollout::Random.new
#
# Example class usage:
#
# class PillColorExperiment < ApplicationExperiment
#   control { }
#   variant(:red) { }
#   variant(:blue) { }
#
#   # Randomize between all behaviors, with a mostly even distribution).
#   default_rollout :random
# end
#
module Gitlab
  class Experiment
    module Rollout
      class Random < Base
        protected

        def execute_assignment
          behavior_names.sample # pick a random variant
        end
      end
    end
  end
end
