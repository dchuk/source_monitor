# frozen_string_literal: true

require "test_helper"
require "pathname"
require "source_monitor/release/runner"

module SourceMonitor
  module Release
    class RunnerTest < ActiveSupport::TestCase
      class RecordingExecutor
        attr_reader :commands, :captured_annotation

        def initialize(failure_at: nil)
          @commands = []
          @failure_at = failure_at
          @invocation_count = 0
        end

        def run(command, env: {})
          @invocation_count += 1
          @commands << { command:, env: }
          capture_annotation(command)

          return false if @failure_at&.==(@invocation_count)

          true
        end

        private

        def capture_annotation(command)
          annotation_path_index = command.index("-F")
          return unless annotation_path_index

          annotation_path = command.fetch(annotation_path_index + 1, nil)
          @captured_annotation = File.exist?(annotation_path) ? File.read(annotation_path) : nil
        end
      end

      class StubbedChangelog
        attr_reader :calls

        def initialize(annotation)
          @annotation = annotation
          @calls = []
        end

        def annotation_for(version)
          @calls << version
          @annotation
        end
      end

      def test_runs_release_sequence_and_creates_annotated_tag
        executor = RecordingExecutor.new
        changelog = StubbedChangelog.new("Release notes go here.")

        Runner.new(version: "1.2.3", executor:, changelog:).call

        assert_equal [ "1.2.3" ], changelog.calls

        commands = executor.commands.map { |entry| entry[:command] }

        assert_equal [ "bin/rubocop" ], commands[0]
        assert_equal [ "bin/brakeman", "--no-pager" ], commands[1]
        assert_equal [ "bin/test-coverage" ], commands[2]
        assert_equal [ "bin/check-diff-coverage" ], commands[3]
        assert_equal [ "rbenv", "exec", "gem", "build", "source_monitor.gemspec" ], commands[4]

        git_tag_command = commands[5]
        assert_equal [ "git", "tag", "-a", "v1.2.3", "-F" ], git_tag_command[0..4]
        assert Pathname.new(git_tag_command[5]).absolute?
        assert_equal "Release notes go here.", executor.captured_annotation
      end

      def test_raises_when_command_fails
        executor = RecordingExecutor.new(failure_at: 3)
        changelog = StubbedChangelog.new("Release notes go here.")

        error = assert_raises(Runner::CommandFailure) do
          Runner.new(version: "1.2.3", executor:, changelog:).call
        end

        assert_match(/Command failed: bin\/test-coverage/, error.message)
      end
    end
  end
end
