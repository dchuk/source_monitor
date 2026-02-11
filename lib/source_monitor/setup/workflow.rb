# frozen_string_literal: true

require "pathname"

module SourceMonitor
  module Setup
    class Workflow
      DEFAULT_MOUNT_PATH = "/source_monitor".freeze

      class RequirementError < StandardError
        attr_reader :summary

        def initialize(summary)
          @summary = summary
          super(build_message)
        end

        private

        def build_message
          messages = summary.errors.map do |result|
            "#{result.name}: #{result.remediation}".strip
          end
          "Setup requirements failed. #{messages.join(' ')}"
        end
      end

      def initialize(
        dependency_checker: DependencyChecker.new,
        prompter: Prompter.new,
        gemfile_editor: GemfileEditor.new,
        bundle_installer: BundleInstaller.new,
        node_installer: NodeInstaller.new,
        install_generator: InstallGenerator.new,
        migration_installer: MigrationInstaller.new,
        initializer_patcher: InitializerPatcher.new,
        devise_detector: method(:default_devise_detector),
        verifier: Verification::Runner.new
      )
        @dependency_checker = dependency_checker
        @prompter = prompter
        @gemfile_editor = gemfile_editor
        @bundle_installer = bundle_installer
        @node_installer = node_installer
        @install_generator = install_generator
        @migration_installer = migration_installer
        @initializer_patcher = initializer_patcher
        @devise_detector = devise_detector
        @verifier = verifier
      end

      def run
        summary = dependency_checker.call
        raise RequirementError, summary if summary.errors?

        mount_path = prompter.ask("Mount SourceMonitor at which path?", default: DEFAULT_MOUNT_PATH)

        gemfile_editor.ensure_entry
        bundle_installer.install
        node_installer.install_if_needed
        install_generator.run(mount_path: mount_path)
        migration_installer.install
        initializer_patcher.ensure_navigation_hint(mount_path: mount_path)

        if devise_available? && prompter.yes?("Wire Devise authentication hooks into SourceMonitor?", default: true)
          initializer_patcher.ensure_devise_hooks
        end

        verifier.call
      end

      private

      attr_reader :dependency_checker,
        :prompter,
        :gemfile_editor,
        :bundle_installer,
        :node_installer,
        :install_generator,
        :migration_installer,
        :initializer_patcher,
        :devise_detector,
        :verifier

      def devise_available?
        !!devise_detector.call
      end

      def default_devise_detector
        Gem.loaded_specs.key?("devise") || gemfile_mentions_devise?
      end

      def gemfile_mentions_devise?
        gemfile = Pathname.new("Gemfile")
        gemfile.exist? && gemfile.read.include?("devise")
      rescue StandardError
        false
      end
    end
  end
end
