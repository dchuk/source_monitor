# frozen_string_literal: true

module SourceMonitor
  module Setup
    class UpgradeCommand
      def initialize(
        migration_installer: MigrationInstaller.new,
        install_generator: InstallGenerator.new,
        verifier: Verification::Runner.new,
        version_file: File.join(Dir.pwd, ".source_monitor_version"),
        current_version: SourceMonitor::VERSION
      )
        @migration_installer = migration_installer
        @install_generator = install_generator
        @verifier = verifier
        @version_file = version_file
        @current_version = current_version
      end

      def call
        stored = read_stored_version

        if stored == current_version
          return up_to_date_summary
        end

        migration_installer.install
        install_generator.run
        summary = verifier.call
        write_version_marker
        summary
      end

      private

      attr_reader :migration_installer, :install_generator, :verifier, :version_file, :current_version

      def read_stored_version
        return nil unless File.exist?(version_file)

        File.read(version_file).strip
      end

      def write_version_marker
        File.write(version_file, current_version)
      end

      def up_to_date_summary
        result = Verification::Result.new(
          key: :upgrade,
          name: "Upgrade",
          status: :ok,
          details: "Already up to date (v#{current_version})"
        )
        Verification::Summary.new([ result ])
      end
    end
  end
end
