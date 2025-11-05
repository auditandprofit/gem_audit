# frozen_string_literal: true

require 'toml-rb'
require 'logger'

module Gitlab
  module SecretDetection
    module Core
      class Ruleset
        # RulesetParseError is thrown when the code fails to parse the
        # ruleset file from the given path
        RulesetParseError = Class.new(StandardError)

        # RulesetCompilationError is thrown when the code fails to compile
        # the predefined rulesets
        RulesetCompilationError = Class.new(StandardError)

        # file path where the secrets ruleset file is located
        RULESET_FILE_PATH = File.expand_path('secret_push_protection_rules.toml', __dir__)

        def initialize(path: RULESET_FILE_PATH, logger: Logger.new($stdout))
          @path = path
          @logger = logger
        end

        def rules(force_fetch: false)
          return @rule_data unless @rule_data.nil? || force_fetch

          @rule_data = parse_ruleset
        end

        def extract_ruleset_version
          @ruleset_version ||= if File.readable?(RULESET_FILE_PATH)
                                 first_line = File.open(RULESET_FILE_PATH, &:gets)
                                 first_line&.split(":")&.[](1)&.strip
                               end
        rescue StandardError => e
          logger.error(message: "Failed to extract Secret Detection Ruleset version from ruleset file: #{e.message}")
        end

        private

        attr_reader :path, :logger

        # parses given ruleset file and returns the parsed rules
        def parse_ruleset
          logger.info(
            message: "Parsing local ruleset file",
            ruleset_path: RULESET_FILE_PATH
          )
          rules_data = TomlRB.load_file(path, symbolize_keys: true).freeze
          ruleset_version = extract_ruleset_version

          logger.info(
            message: "Ruleset details fetched for running Secret Detection scan",
            total_rules: rules_data[:rules]&.length,
            ruleset_version:
          )
          rules_data[:rules].freeze
        rescue StandardError => e
          logger.error(message: "Failed to parse local secret detection ruleset: #{e.message}")
          raise RulesetParseError, e
        end
      end
    end
  end
end
