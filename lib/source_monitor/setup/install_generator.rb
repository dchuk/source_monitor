# frozen_string_literal: true

module SourceMonitor
  module Setup
    class InstallGenerator
      def initialize(shell: ShellRunner.new)
        @shell = shell
      end

      def run(mount_path: Workflow::DEFAULT_MOUNT_PATH)
        shell.run(
          "bin/rails",
          "generate",
          "source_monitor:install",
          "--mount-path=#{mount_path}"
        )
      end

      private

      attr_reader :shell
    end
  end
end
