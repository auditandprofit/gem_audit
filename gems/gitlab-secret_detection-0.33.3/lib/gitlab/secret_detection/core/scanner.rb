# frozen_string_literal: true

require 're2'
require 'logger'
require 'timeout'
require 'English'
require 'parallel'

module Gitlab
  module SecretDetection
    module Core
      # Scan is responsible for running Secret Detection scan operation
      class Scanner
        # default time limit(in seconds) for running the scan operation per invocation
        DEFAULT_SCAN_TIMEOUT_SECS = 180 # 3 minutes
        # default time limit(in seconds) for running the scan operation on a single payload
        DEFAULT_PAYLOAD_TIMEOUT_SECS = 30 # 30 seconds
        # Tags used for creating default pattern matcher
        DEFAULT_PATTERN_MATCHER_TAGS = ['gitlab_blocking'].freeze
        # Max no of child processes to spawn per request
        # ref: https://gitlab.com/gitlab-org/gitlab/-/issues/430160
        MAX_PROCS_PER_REQUEST = 5
        # Minimum cumulative size of the payloads required to spawn and
        # run the scan within a new subprocess.
        MIN_CHUNK_SIZE_PER_PROC_BYTES = 2_097_152 # 2MiB
        # Whether to run scan in subprocesses or not. Default is false.
        RUN_IN_SUBPROCESS = ENV.fetch('GITLAB_SD_RUN_IN_SUBPROCESS', false)
        # Default limit for max findings to be returned in the scan
        DEFAULT_MAX_FINDINGS_LIMIT = 999

        # Initializes the instance with logger along with following operations:
        # 1. Extract keywords from the parsed ruleset to use it for matching keywords before regex operation.
        # 2. Build and Compile rule regex patterns obtained from the ruleset with +DEFAULT_PATTERN_MATCHER_TAGS+
        # tags. Raises +RulesetCompilationError+ in case the regex pattern compilation fails.
        def initialize(rules:, logger: Logger.new($stdout))
          @logger = logger
          @rules = rules
          @keywords = create_keywords(rules)
          @default_keyword_matcher = build_keyword_matcher(
            tags: DEFAULT_PATTERN_MATCHER_TAGS,
            include_missing_tags: false
          )
          @default_pattern_matcher, @default_rules = build_pattern_matcher(
            tags: DEFAULT_PATTERN_MATCHER_TAGS,
            include_missing_tags: false
          ) # includes only gitlab_blocking rules
        end

        # Runs Secret Detection scan on the list of given payloads. Both the total scan duration and
        # the duration for each payload is time bound via +timeout+ and +payload_timeout+ respectively.
        #
        # +payloads+:: Array of payloads where each payload should have `id` and `data` properties.
        # +timeout+:: No of seconds(accepts floating point for smaller time values) to limit the total scan duration
        # +payload_timeout+:: No of seconds(accepts floating point for smaller time values) to limit
        #                  the scan duration on each payload
        # +exclusions+:: Hash with keys: :raw_value, :rule and values of arrays of either
        #           GRPC::Exclusion objects (when used as a standalone service)
        #           or Security::ProjectSecurityExclusion objects (when used as gem).
        #           :raw_value - Exclusions in the :raw array are the raw values to ignore.
        #           :rule - Exclusions in the :rule array are the rules to exclude from the ruleset used for the scan.
        #           Each rule is represented by its ID. For example: `gitlab_personal_access_token`
        #           for representing Gitlab Personal Access Token. By default, no rule is excluded from the ruleset.
        # +tags+:: Array of tag values to filter from the default ruleset when determining the rules used for the scan.
        #           For example: Add `gitlab_blocking` to include only rules for Push Protection. Defaults to
        #           [`gitlab_blocking`] (+DEFAULT_PATTERN_MATCHER_TAGS+).
        # +max_findings_limit+:: Integer to limit the number of findings to be returned in the scan. Defaults
        #           to 999 (+DEFAULT_MAX_FINDINGS_LIMIT+).
        #
        # NOTE:
        # Running the scan in fork mode primarily focuses on reducing the memory consumption of the scan by
        # offloading regex operations on large payloads to sub-processes. However, it does not assure the improvement
        # in the overall latency of the scan, specifically in the case of smaller payloads, where the overhead of
        # forking a new process adds to the overall latency of the scan instead. More reference on Subprocess-based
        # execution is found here: https://gitlab.com/gitlab-org/gitlab/-/issues/430160.
        #
        # Returns an instance of Gitlab::SecretDetection::Core::Response by following below structure:
        # {
        #     status: One of the Core::Status values
        #     results: [SecretDetection::Finding]
        # }
        #
        def secrets_scan(
          payloads,
          timeout: DEFAULT_SCAN_TIMEOUT_SECS,
          payload_timeout: DEFAULT_PAYLOAD_TIMEOUT_SECS,
          exclusions: {},
          tags: DEFAULT_PATTERN_MATCHER_TAGS,
          subprocess: RUN_IN_SUBPROCESS,
          max_findings_limit: DEFAULT_MAX_FINDINGS_LIMIT
        )
          return Core::Response.new(status: Core::Status::INPUT_ERROR) unless validate_scan_input(payloads)

          # assign defaults since grpc passing zero timeout value to `Timeout.timeout(..)` makes it effectively useless.
          timeout = DEFAULT_SCAN_TIMEOUT_SECS unless timeout.positive?
          payload_timeout = DEFAULT_PAYLOAD_TIMEOUT_SECS unless payload_timeout.positive?
          tags = DEFAULT_PATTERN_MATCHER_TAGS if tags.empty?

          Timeout.timeout(timeout) do
            keyword_matcher = build_keyword_matcher(tags:)

            matched_payloads = filter_by_keywords(keyword_matcher, payloads)

            next Core::Response.new(status: Core::Status::NOT_FOUND) if matched_payloads.empty?

            # the pattern matcher will filter rules by tags so we use the filtered rule list
            pattern_matcher, active_rules = build_pattern_matcher(tags:)

            scan_args = {
              payloads: matched_payloads,
              payload_timeout:,
              pattern_matcher:,
              exclusions:,
              rules: active_rules,
              max_findings_limit:
            }.freeze

            logger.info(
              message: "Scan input parameters for running Secret Detection scan",
              timeout:,
              payload_timeout:,
              given_total_payloads: payloads.length,
              scannable_payloads_post_keyword_filter: matched_payloads.length,
              tags:,
              run_in_subprocess: subprocess,
              max_findings_limit:,
              given_exclusions: format_exclusions_hash(exclusions)
            )

            secrets, applied_exclusions = subprocess ? run_scan_within_subprocess(**scan_args) : run_scan(**scan_args)

            scan_status = overall_scan_status(secrets)

            logger.info(
              message: "Secret Detection scan completed with #{secrets.length} secrets detected in the given payloads",
              detected_secrets_metadata: format_detected_secrets_metadata(secrets),
              applied_exclusions: format_exclusions_arr(applied_exclusions)
            )

            Core::Response.new(status: scan_status, results: secrets, applied_exclusions:)
          end
        rescue Timeout::Error => e
          logger.error "Secret detection operation timed out: #{e}"

          Core::Response.new(status: Core::Status::SCAN_TIMEOUT)
        end

        private

        attr_reader :logger, :rules, :keywords, :default_pattern_matcher, :default_keyword_matcher, :default_rules

        # Builds RE2::Set pattern matcher for the given combination of rules
        # and tags. It also allows a choice(via `include_missing_tags`) to consider rules
        # for pattern matching that do not have `tags` property defined. If the given tags
        # are same as +DEFAULT_PATTERN_MATCHER_TAGS+ then returns the eagerly loaded default
        # pattern matcher created during initialization.
        def build_pattern_matcher(tags:, include_missing_tags: false)
          if tags.eql?(DEFAULT_PATTERN_MATCHER_TAGS) && !default_pattern_matcher.nil?
            logger.info(
              message: "Given tags input matches default matcher tags, using pre-defined RE2 Pattern Matcher"
            )
            return [default_pattern_matcher, default_rules]
          end

          logger.info(
            message: "Creating a new RE2 Pattern Matcher with given tags",
            tags:,
            include_missing_tags:
          )
          active_rules = []

          matcher = RE2::Set.new

          begin
            rules.each do |rule|
              rule_tags = rule[:tags]

              include_rule = if tags.empty?
                               true
                             elsif rule_tags
                               tags.intersect?(rule_tags)
                             else
                               include_missing_tags
                             end

              active_rules << rule if include_rule
              matcher.add(rule[:regex]) if include_rule
            end
          rescue StandardError => e
            logger.error "Failed to add regex secret detection ruleset in RE::Set: #{e.message}"
            raise Core::Ruleset::RulesetCompilationError, cause: e
          end

          unless matcher.compile
            logger.error "Failed to compile secret detection ruleset in RE::Set"

            raise Core::Ruleset::RulesetCompilationError
          end

          [matcher, active_rules]
        end

        # Creates and returns the unique set of rule matching keywords
        def create_keywords(rules)
          secrets_keywords = Set.new

          rules.each do |rule|
            secrets_keywords.merge rule[:keywords] unless rule[:keywords].nil?
          end

          secrets_keywords.freeze
        end

        def build_keyword_matcher(tags:, include_missing_tags: false)
          if tags.eql?(DEFAULT_PATTERN_MATCHER_TAGS) && !default_keyword_matcher.nil?
            logger.info(
              message: "Given tags input matches default tags, using pre-defined RE2 Keyword Matcher"
            )
            return default_keyword_matcher
          end

          logger.info(
            message: "Creating a new RE2 Keyword Matcher..",
            tags:,
            include_missing_tags:
          )

          include_keywords = Set.new

          rules.each do |rule|
            rule_tags = rule.fetch(:tags, [])

            next if rule_tags.empty? && !include_missing_tags
            next unless rule_tags.intersect?(tags)

            include_keywords.merge(rule[:keywords]) unless rule[:keywords].nil?
          end

          if include_keywords.empty?
            logger.error(
              message: "No rule keywords found a match with given rule tags, returning empty RE2 Keyword Matcher"
            )
            return nil
          end

          keywords_regex = include_keywords.map { |keyword| RE2::Regexp.quote(keyword) }.join('|')

          logger.debug(
            message: "Creating RE2 Keyword Matcher with set of rule keywords",
            keywords: include_keywords.to_a
          )

          RE2("(#{keywords_regex})")
        end

        def filter_by_keywords(keyword_matcher, payloads)
          if keyword_matcher.nil?
            logger.warn "No RE2 Keyword Matcher instance available, skipping payload filter by rule keywords step.."
            return payloads
          end

          matched_payloads = []
          payloads.each do |payload|
            next unless keyword_matcher.partial_match?(payload.data)

            matched_payloads << payload
          end

          total_payloads_retained = matched_payloads.length == payloads.length ? 'all' : matched_payloads.length
          log_message = if matched_payloads.empty?
                          "No payloads available to scan further after keyword-matching, exiting Secret Detection scan"
                        else
                          "Retained #{total_payloads_retained} payloads to scan further after keyword-matching step"
                        end

          logger.info(
            message: log_message,
            given_total_payloads: payloads.length,
            matched_payloads: matched_payloads.length,
            payloads_to_scan_further: matched_payloads.map(&:id)
          )

          matched_payloads
        end

        # Runs the secret detection scan on the given list of payloads. It accepts
        # literal values to exclude from the input before the scan, also SD rules to exclude during
        # the scan when performed on the payloads.
        def run_scan(
          payloads:,
          payload_timeout:,
          pattern_matcher:,
          max_findings_limit:,
          exclusions: {},
          rules: [])
          all_applied_exclusions = Set.new

          logger.info(
            message: "Running Secret Detection scan sequentially",
            payload_timeout:
          )

          capped_findings = payloads.lazy.flat_map do |payload|
            Timeout.timeout(payload_timeout) do
              findings, applied_exclusions = find_secrets_in_payload(
                payload:,
                pattern_matcher:,
                exclusions:,
                rules:
              )
              all_applied_exclusions.merge(applied_exclusions)
              findings
            end
          rescue Timeout::Error => e
            logger.warn "Secret Detection scan timed out on the payload(id:#{payload.id}): #{e}"

            Core::Finding.new(payload.id,
              Core::Status::PAYLOAD_TIMEOUT)
          end.take(max_findings_limit).to_a

          [capped_findings, all_applied_exclusions.to_a]
        end

        def run_scan_within_subprocess(
          payloads:,
          payload_timeout:,
          pattern_matcher:,
          max_findings_limit:,
          exclusions: {},
          rules: []
        )
          all_applied_exclusions = Set.new

          payload_sizes = payloads.map(&:size)
          grouped_payload_indices = group_by_chunk_size(payload_sizes)

          grouped_payloads = grouped_payload_indices.map { |idx_arr| idx_arr.map { |i| payloads[i] } }

          logger.info(
            message: "Running Secret Detection scan within a subprocess",
            grouped_payloads: grouped_payloads.length,
            payload_timeout:
          )

          found_secrets = []

          grouped_payloads.each do |grouped_payload|
            break if found_secrets.length >= max_findings_limit

            batch_results = Parallel.map(
              grouped_payload,
              in_processes: MAX_PROCS_PER_REQUEST,
              isolation: true # do not reuse sub-processes
            ) do |payload|
              Timeout.timeout(payload_timeout) do
                findings, applied_exclusions = find_secrets_in_payload(
                  payload:,
                  pattern_matcher:,
                  exclusions:,
                  rules:
                )
                [findings, applied_exclusions]
              end
            rescue Timeout::Error => e
              logger.warn "Secret Detection scan timed out on the payload(id:#{payload.id}): #{e}"

              Core::Finding.new(payload.id, Core::Status::PAYLOAD_TIMEOUT)
            end

            # Process results and collect exclusions
            batch_results.each do |findings, applied_exclusions|
              all_applied_exclusions.merge(applied_exclusions)

              remaining_slots = max_findings_limit - found_secrets.length
              found_secrets.concat(findings.take(remaining_slots))

              break if found_secrets.length >= max_findings_limit
            end
          end

          [found_secrets, all_applied_exclusions.to_a]
        end

        # Finds secrets in the given payload guarded with a timeout as a circuit breaker. It accepts
        # literal values to exclude from the input before the scan, also SD rules to exclude during
        # the scan.
        def find_secrets_in_payload(payload:, pattern_matcher:, exclusions: {}, rules: @default_rules)
          findings = []
          applied_exclusions = Set.new

          payload_offset = payload.respond_to?(:offset) ? payload.offset : 0

          raw_value_exclusions = exclusions.fetch(:raw_value, [])
          rule_exclusions = exclusions.fetch(:rule, [])

          payload.data
                 .each_line($INPUT_RECORD_SEPARATOR, chomp: true)
                 .each_with_index do |line, index|
            unless raw_value_exclusions.empty?
              raw_value_exclusions.each do |exclusion|
                # replace input that doesn't contain allowed value in it
                # replace exclusion value, `.gsub!` returns 'self' if replaced otherwise 'nil'
                excl_replaced = !!line.gsub!(exclusion.value, '')
                applied_exclusions << exclusion if excl_replaced
              end
            end

            next if line.empty?

            # If payload offset is given then we will compute absolute line number i.e.,
            # offset + relative_line_number - 1. In this scenario, index is equivalent to relative_line_number - 1.
            # Whereas, when payload offset is not given, we'll set the line number relative to the beginning of the
            # payload. In this scenario it will be index + 1.
            line_no = payload_offset.positive? ? payload_offset + index : index + 1

            matches = pattern_matcher.match(line, exception: false) # returns indices of matched patterns

            matches.each do |match_idx|
              rule = rules[match_idx]

              next if applied_rule_exclusion?(rule[:id], rule_exclusions, applied_exclusions)

              title = rule[:title].nil? ? rule[:description] : rule[:title]

              findings << Core::Finding.new(
                payload.id,
                Core::Status::FOUND,
                line_no,
                rule[:id],
                title
              )
            end
          end

          logger.info(
            message: "Secret Detection scan found #{findings.length} secret leaks in the payload(id:#{payload.id})",
            payload_id: payload.id,
            detected_rules: findings.map { |f| "#{f.type}:#{f.line_number}" },
            applied_exclusions: format_exclusions_arr(applied_exclusions)
          )

          [findings, applied_exclusions]
        rescue StandardError => e
          logger.error "Secret Detection scan failed on the payload(id:#{payload.id}): #{e}"

          [[Core::Finding.new(payload.id, Core::Status::SCAN_ERROR)], []]
        end

        def applied_rule_exclusion?(type, rule_exclusions, applied_exclusions)
          applied_exclusion = rule_exclusions&.find { |rule_exclusion| rule_exclusion.value == type }
          applied_exclusion && (applied_exclusions << applied_exclusion)
        end

        # Validates the given payloads by verifying the type and
        # presence of `id` and `data` fields necessary for the scan
        def validate_scan_input(payloads)
          if payloads.nil? || !payloads.instance_of?(Array)
            logger.debug(message: "Scan input validation error: payloads arg is empty or not instance of array")
            return false
          end

          payloads.all? do |payload|
            has_valid_fields = payload.respond_to?(:id) && payload.respond_to?(:data) && payload.data.is_a?(String)
            unless has_valid_fields
              logger.debug(
                message: "Scan input validation error: one of the payloads does not respond to `id` or `data`"
              )
            end

            has_valid_fields
          end
        end

        # Returns the status of the overall scan request
        # based on the detected secret findings found in the input payloads
        def overall_scan_status(found_secrets)
          return Core::Status::NOT_FOUND if found_secrets.empty?

          timed_out_payloads = found_secrets.count { |el| el.status == Core::Status::PAYLOAD_TIMEOUT }

          case timed_out_payloads
          when 0
            Core::Status::FOUND
          when found_secrets.length
            Core::Status::SCAN_TIMEOUT
          else
            Core::Status::FOUND_WITH_ERRORS
          end
        end

        # This method accepts an array of payload sizes(in bytes) and groups them into an array
        # of arrays structure where each element is the group of indices of the input
        # array whose cumulative payload sizes has at least +MIN_CHUNK_SIZE_PER_PROC_BYTES+
        def group_by_chunk_size(payload_size_arr)
          cumulative_size = 0
          chunk_indexes = []
          chunk_idx_start = 0

          payload_size_arr.each_with_index do |size, index|
            cumulative_size += size
            next unless cumulative_size >= MIN_CHUNK_SIZE_PER_PROC_BYTES

            chunk_indexes << (chunk_idx_start..index).to_a

            chunk_idx_start = index + 1
            cumulative_size = 0
          end

          if cumulative_size.positive? && (chunk_idx_start < payload_size_arr.length)
            chunk_indexes << if chunk_idx_start == payload_size_arr.length - 1
                               [chunk_idx_start]
                             else
                               (chunk_idx_start..payload_size_arr.length - 1).to_a
                             end
          end

          chunk_indexes
        end

        # Returns array of strings with each representing a masked exclusion
        #
        # Example: For given arg exclusions = {
        #     rule: ["gitlab_personal_access_token", "aws_key"],
        #     path: ["test.py"],
        #     raw_value: ["ABC123XYZ"]
        # }
        #
        # The output will look like the following:
        # [
        #   "rule=gitlab_personal_access_token,aws_key",
        #   "raw_value=AB*****YZ",
        #   "paths=test.py"
        # ]
        def format_exclusions_hash(exclusions = {})
          masked_raw_values = exclusions.fetch(:raw_value, []).map do |exclusion|
            Gitlab::SecretDetection::Utils::Masker.mask_secret(exclusion.value)
          end.join(", ")
          paths = exclusions.fetch(:path, []).map(&:value).join(", ")
          rules = exclusions.fetch(:rule, []).map(&:value).join(", ")

          out = []

          out << "rules=#{rules}" unless rules.empty?
          out << "raw_values=#{masked_raw_values}" unless masked_raw_values.empty?
          out << "paths=#{paths}" unless paths.empty?

          out
        end

        def format_exclusions_arr(exclusions = [])
          return [] if exclusions.empty?

          masked_raw_values = Set.new
          paths = Set.new
          rules = Set.new

          exclusions.each do |exclusion|
            case exclusion.exclusion_type
            when :EXCLUSION_TYPE_RAW_VALUE
              masked_raw_values << Gitlab::SecretDetection::Utils::Masker.mask_secret(exclusion.value)
            when :EXCLUSION_TYPE_RULE
              rules << exclusion.value
            when :EXCLUSION_TYPE_PATH
              paths << exclusion.value
            else
              logger.warn("Unknown exclusion type #{exclusion.exclusion_type}")
            end
          end

          out = []

          out << "rules=#{rules.join(',')}" unless rules.empty?
          out << "raw_values=#{masked_raw_values.join(',')}" unless masked_raw_values.empty?
          out << "paths=#{paths.join(',')}" unless paths.empty?

          out
        end

        def format_detected_secrets_metadata(findings = [])
          return [] if findings.empty?

          found_secrets = findings.filter do |f|
            f.status == Core::Status::FOUND
          end

          found_secrets.map { |f| "#{f.payload_id}=>#{f.type}:#{f.line_number}" }
        end
      end
    end
  end
end
