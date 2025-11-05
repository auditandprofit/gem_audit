# frozen_string_literal: true

require "net/http"
require "json"

require_relative "capability"

module Gitlab
  module Dangerfiles
    class Teammate
      ROULETTE_DATA_URL = "https://gitlab-org.gitlab.io/gitlab-roulette/roulette.json"

      def self.find_member(username, project: nil)
        company_members.find do |member|
          member.username == username &&
            (project.nil? || member.in_project?(project))
        end
      end

      def self.has_member_for_the_group?(category, labels:, **arguments)
        capabilities = %i[reviewer maintainer].map do |kind|
          # Use new to use the base class for original has_capability? method
          Capability.new(category: category, kind: kind, labels: labels, **arguments)
        end

        company_members.any? do |teammate|
          capabilities.any? do |capability|
            capability.has_capability?(teammate) &&
              teammate.member_of_the_group?(labels)
          end
        end
      end

      # Looks up the current list of GitLab team members and parses it into a
      # useful form.
      #
      # @return [Array<Gitlab::Dangerfiles::Teammate>]
      def self.company_members
        @company_members ||= fetch_company_members
      end

      def self.fetch_company_members
        data = http_get_json(ROULETTE_DATA_URL) || []
        data.map { |hash| Teammate.new(hash) }
      rescue JSON::ParserError
        warnings << "Failed to parse JSON response from #{ROULETTE_DATA_URL}"
        []
      end

      # Fetches the given +url+ and parse its response as JSON.
      #
      # @param [String] url
      #
      # @return [Hash, Array, NilClass]
      def self.http_get_json(url)
        rsp = Net::HTTP.get_response(URI.parse(url))

        if rsp.is_a?(Net::HTTPRedirection)
          uri = URI.parse(rsp.header["location"])

          uri.query = nil if uri

          warnings << "Redirection detected: #{uri}."
          return nil
        end

        unless rsp.is_a?(Net::HTTPOK)
          message = rsp.message[0, 30]
          warnings << "HTTPError: Failed to read #{url}: #{rsp.code} #{message}."
          return nil
        end

        JSON.parse(rsp.body)
      end

      def self.warnings
        @warnings ||= []
      end

      attr_reader :options, :username, :name, :role, :specialty, :projects, :available, :hungry, :reduced_capacity, :tz_offset_hours,
        :only_maintainer_reviews

      # The options data are produced by https://gitlab.com/gitlab-org/gitlab-roulette/-/blob/main/lib/team_member.rb
      def initialize(options = {})
        @options = options
        @username = options["username"]
        @name = options["name"]
        @markdown_name = options["markdown_name"] ||
          default_markdown_name(options["username"])
        @role = options["role"]
        @specialty = options["specialty"]
        @projects = process_projects(options["projects"])
        @available = options["available"]
        @hungry = options["hungry"]
        @reduced_capacity = options["reduced_capacity"]
        @tz_offset_hours = options["tz_offset_hours"]
        @only_maintainer_reviews = options["only_maintainer_reviews"]
      end

      def member_of_the_group?(labels)
        # Specialty can be:
        # Source Code
        # [Growth: Activation, Growth: Expansion]
        # Runner
        group_labels = Array(specialty).map do |field|
          group = field.strip.sub(/^.+: ?/, "").downcase

          "group::#{group}"
        end

        (group_labels & labels).any?
      end

      def to_h
        options
      end

      def inspect
        "#<#{self.class} @username=#{username.inspect}>"
      end

      def ==(other)
        return false unless other.respond_to?(:username)

        other.username == username
      end

      def in_project?(name)
        projects&.has_key?(name)
      end

      def reviewer?(project, category, labels)
        has_capability?(project, category, :reviewer, labels)
      end

      def traintainer?(project, category, labels)
        has_capability?(project, category, :trainee_maintainer, labels)
      end

      def maintainer?(project, category, labels)
        has_capability?(project, category, :maintainer, labels)
      end

      def markdown_name(author: nil)
        "#{@markdown_name}#{utc_offset_text(author)}"
      end

      def local_hour
        (Time.now.utc + tz_offset_hours * 3600).hour
      end

      def capabilities(project)
        projects.fetch(project, [])
      end

      protected

      def floored_offset_hours
        floored_offset = tz_offset_hours.floor(0)

        floored_offset == tz_offset_hours ? floored_offset : tz_offset_hours
      end

      private

      def default_markdown_name(username)
        "`@#{username}` [![profile link](https://gitlab.com/gitlab-org/gitlab-svgs/-/raw/main/sprite_icons/user.svg?ref_type=heads)](https://gitlab.com/#{username})"
      end

      def process_projects(projects)
        return nil unless projects

        projects.each_with_object({}) do |(project, capabilities), all|
          all[project.downcase] = Array(capabilities).map(&:downcase)
        end
      end

      def utc_offset_text(author = nil)
        return unless tz_offset_hours

        offset_text = if floored_offset_hours >= 0
            "UTC+#{floored_offset_hours}"
          else
            "UTC#{floored_offset_hours}"
          end

        if author
          " (#{offset_text}, #{offset_diff_compared_to_author(author)})"
        else
          " (#{offset_text})"
        end
      end

      def offset_diff_compared_to_author(author)
        diff = floored_offset_hours - author.floored_offset_hours
        return "same timezone as author" if diff == 0

        ahead_or_behind = diff < 0 ? "behind" : "ahead of"
        pluralized_hours = pluralize(diff.abs, "hour", "hours")

        "#{pluralized_hours} #{ahead_or_behind} author"
      end

      def has_capability?(project, category, kind, labels)
        Capability.for(category, project: project, kind: kind, labels: labels).has_capability?(self)
      end

      def pluralize(count, singular, plural)
        word = count == 1 || count.to_s =~ /^1(\.0+)?$/ ? singular : plural

        "#{count || 0} #{word}"
      end
    end
  end
end
