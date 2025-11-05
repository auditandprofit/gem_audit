require "gitlab/dangerfiles/version"
require "gitlab/dangerfiles/task_loader"

module Gitlab
  module Dangerfiles
    RULES_DIR = File.expand_path("../danger/rules", __dir__)
    CI_ONLY_RULES = %w[
      metadata
      simple_roulette
      type_label
      z_add_labels
      z_retry_link
    ].freeze

    def self.load_tasks
      TaskLoader.load_tasks
    end

    # Utility method to construct a [Gitlab::Dangerfiles::Engine] instance,
    # which is yielded to the given block.
    #
    # @param dangerfile [Danger::Dangerfile] A +Danger::Dangerfile+ object.
    # @param project_name An option string to set the project name. Defaults to +ENV['CI_PROJECT_NAME']+.
    #
    # @return [Gitlab::Dangerfiles::Engine]
    def self.for_project(dangerfile, project_name = nil)
      Engine.new(dangerfile).tap do |engine|
        engine.config.project_root = Pathname.new(File.dirname(dangerfile.defined_in_file))
        engine.config.project_name = project_name if project_name

        yield engine
      end
    end

    # This class provides utility methods to import plugins and dangerfiles easily.
    class Engine
      # @param dangerfile [Danger::Dangerfile] A +Danger::Dangerfile+ object.
      #
      # @example
      #   # In your main Dangerfile:
      #   dangerfiles = Gitlab::Dangerfiles::Engine.new(self)
      #
      # @return [Gitlab::Dangerfiles::Engine]
      def initialize(dangerfile)
        @dangerfile = dangerfile

        # Import internal plugins eagerly, since other functionality in this class may depend on them.
        danger_plugin.import_plugin(File.expand_path("../danger/plugins/internal/*.rb", __dir__))
      end

      # Import all available plugins.
      #
      # @example
      #   # In your main Dangerfile:
      #   Gitlab::Dangerfiles.for_project(self) do |dangerfiles|
      #     dangerfiles.import_plugins
      #   end
      def import_plugins
        danger_plugin.import_plugin(File.expand_path("../danger/plugins/*.rb", __dir__))

        Dir.glob(File.expand_path("danger/plugins/*.rb", config.project_root)).sort.each do |path|
          puts "Importing plugin at #{path}" if helper_plugin.ci?
          danger_plugin.import_plugin(path)
        end
      end

      # Import available Dangerfiles.
      #
      # @param only [Symbol, Array<String>] An array of rules to import (defaults to all rules).
      #   Available rules are: +changes_size+.
      #
      # @param except [Symbol, Array<String>] An array of rules to not import (defaults to []).
      #   Available rules are: +changes_size+.
      #
      # @example
      #   # In your main Dangerfile:
      #   Gitlab::Dangerfiles.for_project(self) do |dangerfiles|
      #     # Import all rules
      #     dangerfiles.import_dangerfiles
      #     # Or import only a subset of rules
      #     dangerfiles.import_dangerfiles(only: %w[changes_size])
      #     # Or import all rules except a subset of rules
      #     dangerfiles.import_dangerfiles(except: %w[commit_messages])
      #     # Or import only a subset of rules, except a subset of rules
      #     dangerfiles.import_dangerfiles(only: %w[changes_size], except: %w[commit_messages])
      #   end
      def import_dangerfiles(only: nil, except: [])
        return if helper_plugin.release_automation?

        rules = filtered_rules(only, except)

        rules.each do |rule, path|
          puts "Importing rule #{rule} at #{path}" if helper_plugin.ci?
          danger_plugin.import_dangerfile(path: path)
        end
      end

      # Proxy method to +helper_plugin.config+.
      def config
        helper_plugin.config
      end

      # Imports all default plugins and rules.
      #
      # @example
      #   # In your main Dangerfile:
      #   Gitlab::Dangerfiles.for_project(self) do |dangerfiles|
      #     dangerfiles.import_defaults
      #   end
      def import_defaults
        import_plugins
        import_dangerfiles
      end

      private

      attr_reader :dangerfile

      def filtered_rules(only_rules, except_rules)
        only_rules = Array(only_rules).compact.map(&:to_s)

        rules = allowed_rules_based_on_context.reject { |rule, _v| except_rules.include?(rule) }

        if only_rules.any?
          rules.select! { |rule, _v| only_rules.include?(rule) }
        end

        rules.sort.to_h
      end

      def allowed_rules_based_on_context
        helper_plugin.ci? ? all_rules : local_rules
      end

      def all_rules
        all_gem_rules.merge(custom_rules)
      end

      def all_gem_rules
        @all_gem_rules ||= Dir.glob(File.join(RULES_DIR, "*")).each_with_object({}) do |path, memo|
          rule_name = File.basename(path)
          memo[rule_name] = path if File.directory?(path) && File.exist?(File.join(path, "Dangerfile"))
        end
      end

      def custom_rules
        @custom_rules ||= Dir.glob(File.expand_path("danger/*", config.project_root)).each_with_object({}) do |path, memo|
          rule_name = File.basename(path)
          memo[rule_name] = path if File.directory?(path) && File.exist?(File.join(path, "Dangerfile"))
        end
      end

      def local_rules
        ci_only_rules = CI_ONLY_RULES | config.ci_only_rules
        all_rules.reject { |rule, _v| ci_only_rules.include?(rule) }
      end

      def danger_plugin
        @danger_plugin ||= dangerfile.plugins[Danger::DangerfileDangerPlugin]
      end

      def helper_plugin
        @helper_plugin ||= dangerfile.plugins[Danger::Helper]
      end
    end
  end
end
