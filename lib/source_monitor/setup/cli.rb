# frozen_string_literal: true

require "thor"

module SourceMonitor
  module Setup
    class CLI < Thor
      class_option :yes, type: :boolean, default: false, desc: "Accept all defaults"

      desc "install", "Run the guided SourceMonitor setup workflow"
      option :mount_path, type: :string, default: Workflow::DEFAULT_MOUNT_PATH
      def install
        workflow = Workflow.new(
          prompter: Prompter.new(shell: shell, auto_yes: options[:yes])
        )
        summary = workflow.run
        handle_summary(summary)
      end

      desc "verify", "Verify queue workers and Action Cable configuration"
      def verify
        summary = verification_runner.call
        handle_summary(summary)
      end

      desc "upgrade", "Upgrade SourceMonitor after a gem version change"
      def upgrade
        command = UpgradeCommand.new
        summary = command.call
        handle_summary(summary)
      end

      private

      def handle_summary(summary)
        printer.print(summary)
        emit_telemetry(summary)
        exit(1) unless summary.ok?
      end

      def printer
        Verification::Printer.new(shell: shell)
      end

      def verification_runner
        Verification::Runner.new
      end

      def emit_telemetry(summary)
        return unless telemetry_enabled?

        Verification::TelemetryLogger.new.log(summary)
      end

      def telemetry_enabled?
        ENV["SOURCE_MONITOR_SETUP_TELEMETRY"].to_s.casecmp("true").zero?
      end
    end
  end
end
