# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    module Verification
      class PrinterTest < ActiveSupport::TestCase
        class FakeShell
          attr_reader :messages

          def initialize
            @messages = []
          end

          def say(message)
            @messages << message
          end
        end

        test "prints each result" do
          shell = FakeShell.new
          summary = Summary.new([
            Result.new(key: :demo, name: "Demo", status: :ok, details: "fine")
          ])

          Printer.new(shell: shell).print(summary)

          assert_includes shell.messages.first, "Verification summary"
          assert_includes shell.messages[-2], "Demo"
          assert_includes shell.messages.last, '"overall_status":"ok"'
        end
      end
    end
  end
end
