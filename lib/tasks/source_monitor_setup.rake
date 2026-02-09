# frozen_string_literal: true

namespace :source_monitor do
  namespace :setup do
    desc "Verify host dependencies before running the guided SourceMonitor installer"
    task check: :environment do
      summary = SourceMonitor::Setup::DependencyChecker.new.call

      puts "SourceMonitor dependency check:" # rubocop:disable Rails/Output
      summary.results.each do |result|
        status = result.status.to_s.upcase
        current = result.current ? result.current.to_s : "missing"
        expected = result.expected || "n/a"
        puts "- #{result.name}: #{status} (current: #{current}, required: #{expected})" # rubocop:disable Rails/Output
      end

      if summary.errors?
        messages = summary.errors.map do |result|
          "#{result.name}: #{result.remediation}"
        end

        raise "SourceMonitor setup requirements failed. #{messages.join(' ')}"
      end
    end

    desc "Verify queue workers, Action Cable, and telemetry hooks"
    task verify: :environment do
      summary = SourceMonitor::Setup::Verification::Runner.new.call
      printer = SourceMonitor::Setup::Verification::Printer.new
      printer.print(summary)

      if ENV["SOURCE_MONITOR_SETUP_TELEMETRY"].present?
        SourceMonitor::Setup::Verification::TelemetryLogger.new.log(summary)
      end

      unless summary.ok?
        raise "SourceMonitor setup verification failed. See output above for remediation steps."
      end
    end
  end
end
