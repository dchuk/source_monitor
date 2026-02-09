# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    class PrompterTest < ActiveSupport::TestCase
      class FakeShell
        attr_reader :questions

        def initialize(responses)
          @responses = responses
          @questions = []
        end

        def ask(prompt)
          @questions << prompt
          @responses.shift.to_s
        end
      end

      test "ask returns default when blank" do
        shell = FakeShell.new([ "\n" ])
        prompter = Prompter.new(shell: shell)

        assert_equal "/source_monitor", prompter.ask("Mount?", default: "/source_monitor")
      end

      test "yes? parses responses" do
        shell = FakeShell.new([ "yes", "no" ])
        prompter = Prompter.new(shell: shell)

        assert prompter.yes?("Wire Devise?", default: true)
        refute prompter.yes?("Wire Devise?", default: true)
      end
    end
  end
end
