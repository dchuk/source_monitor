# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    class CLITest < ActiveSupport::TestCase
      test "install command delegates to workflow and prints summary" do
        workflow = Minitest::Mock.new
        summary = SourceMonitor::Setup::Verification::Summary.new([])
        workflow.expect(:run, summary)

        printer = Minitest::Mock.new
        printer.expect(:print, nil, [ summary ])

        SourceMonitor::Setup::Workflow.stub(:new, ->(*) { workflow }) do
          SourceMonitor::Setup::Verification::Printer.stub(:new, printer) do
            CLI.start([ "install", "--mount-path=/monitor" ])
          end
        end

        workflow.verify
        printer.verify
        assert_mock workflow
        assert_mock printer
      end

      test "verify command runs runner" do
        summary = SourceMonitor::Setup::Verification::Summary.new([])
        runner = Minitest::Mock.new
        runner.expect(:call, summary)
        printer = Minitest::Mock.new
        printer.expect(:print, nil, [ summary ])

        SourceMonitor::Setup::Verification::Runner.stub(:new, ->(*) { runner }) do
          SourceMonitor::Setup::Verification::Printer.stub(:new, printer) do
            CLI.start([ "verify" ])
          end
        end

        runner.verify
        printer.verify
        assert_mock runner
        assert_mock printer
      end

      test "upgrade command delegates to upgrade command and prints summary" do
        summary = SourceMonitor::Setup::Verification::Summary.new([])
        upgrade_cmd = Minitest::Mock.new
        upgrade_cmd.expect(:call, summary)
        printer = Minitest::Mock.new
        printer.expect(:print, nil, [ summary ])

        SourceMonitor::Setup::UpgradeCommand.stub(:new, ->(*) { upgrade_cmd }) do
          SourceMonitor::Setup::Verification::Printer.stub(:new, printer) do
            CLI.start([ "upgrade" ])
          end
        end

        upgrade_cmd.verify
        printer.verify
        assert_mock upgrade_cmd
        assert_mock printer
      end

      test "handle_summary exits when summary not ok" do
        cli = CLI.new
        summary = Minitest::Mock.new
        summary.expect(:ok?, false)
        printer = Minitest::Mock.new
        printer.expect(:print, nil, [ summary ])
        cli.stub(:printer, printer) do
          cli.stub(:emit_telemetry, nil) do
            exit_status = nil
            cli.stub(:exit, ->(status) { exit_status = status }) do
              cli.send(:handle_summary, summary)
            end

            assert_equal 1, exit_status
            summary.verify
            assert_mock printer
          end
        end
      end

      test "handle_summary logs telemetry when env opt in" do
        cli = CLI.new
        summary = Minitest::Mock.new
        summary.expect(:ok?, true)

        printer = Minitest::Mock.new
        printer.expect(:print, nil, [ summary ])

        logger = Minitest::Mock.new
        logger.expect(:log, nil, [ summary ])

        ENV["SOURCE_MONITOR_SETUP_TELEMETRY"] = "true"
        cli.stub(:printer, printer) do
          SourceMonitor::Setup::Verification::TelemetryLogger.stub(:new, logger) do
            cli.stub(:exit, nil) do
              cli.send(:handle_summary, summary)
            end
          end
        end
        summary.verify
        logger.verify
        assert_mock printer
        assert_mock logger
      ensure
        ENV.delete("SOURCE_MONITOR_SETUP_TELEMETRY")
      end
    end
  end
end
