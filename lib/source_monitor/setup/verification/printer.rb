# frozen_string_literal: true

module SourceMonitor
  module Setup
    module Verification
      class Printer
        def initialize(shell: Thor::Shell::Basic.new)
          @shell = shell
        end

        def print(summary)
          shell.say("Verification summary (#{summary.overall_status.upcase}):")
          summary.results.each do |result|
            shell.say("- #{result.name}: #{result.status.upcase} - #{result.details}")
            shell.say("  Remediation: #{result.remediation}") if result.remediation.present?
          end
          shell.say("JSON: #{summary.to_json}")
        end

        private

        attr_reader :shell
      end
    end
  end
end
