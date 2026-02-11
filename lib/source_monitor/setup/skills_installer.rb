# frozen_string_literal: true

require "fileutils"
require "pathname"

module SourceMonitor
  module Setup
    class SkillsInstaller
      SM_SKILL_PATTERN = "sm-*"

      CONSUMER_SKILLS = %w[
        sm-host-setup sm-configure sm-scraper-adapter
        sm-event-handler sm-model-extension sm-dashboard-widget
      ].freeze

      CONTRIBUTOR_SKILLS = %w[
        sm-domain-model sm-architecture sm-engine-test
        sm-configuration-setting sm-pipeline-stage sm-engine-migration
        sm-job sm-health-rule
      ].freeze

      def initialize(gem_root: nil, output: $stdout)
        @gem_root = Pathname.new(gem_root || resolve_gem_root)
        @output = output
      end

      def install(target_dir:, group: :consumer)
        target = Pathname.new(target_dir)
        result = { installed: [], skipped: [] }

        source_skills_dir = gem_root.join(".claude", "skills")
        return result unless source_skills_dir.directory?

        skill_dirs = Dir[source_skills_dir.join(SM_SKILL_PATTERN).to_s].sort
        return result if skill_dirs.empty?

        allowed = skills_for_group(group)
        skill_dirs = skill_dirs.select { |path| allowed.include?(File.basename(path)) }
        return result if skill_dirs.empty?

        FileUtils.mkdir_p(target.to_s)

        skill_dirs.each do |source_path|
          skill_name = File.basename(source_path)
          dest_path = target.join(skill_name)

          if dest_path.directory?
            result[:skipped] << skill_name
          else
            FileUtils.cp_r(source_path, dest_path.to_s)
            result[:installed] << skill_name
          end
        end

        result
      end

      def remove(target_dir:)
        target = Pathname.new(target_dir)
        result = { removed: [] }

        return result unless target.directory?

        Dir[target.join(SM_SKILL_PATTERN).to_s].sort.each do |path|
          skill_name = File.basename(path)
          FileUtils.rm_rf(path)
          result[:removed] << skill_name
        end

        result
      end

      private

      attr_reader :gem_root, :output

      def skills_for_group(group)
        case group
        when :consumer then CONSUMER_SKILLS
        when :contributor then CONTRIBUTOR_SKILLS
        when :all then CONSUMER_SKILLS + CONTRIBUTOR_SKILLS
        else raise ArgumentError, "Unknown skill group: #{group.inspect}. Use :consumer, :contributor, or :all"
        end
      end

      def resolve_gem_root
        spec = Gem.loaded_specs["source_monitor"]
        return spec.gem_dir if spec

        File.expand_path("../../..", __dir__)
      end
    end
  end
end
