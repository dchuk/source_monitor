# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    class InstallGeneratorTest < ActiveSupport::TestCase
      class FakeShell
        attr_reader :commands

        def initialize
          @commands = []
        end

        def run(*command)
          @commands << command
          ""
        end
      end

      test "runs install generator with mount path" do
        shell = FakeShell.new
        generator = InstallGenerator.new(shell: shell)

        generator.run(mount_path: "/admin/source_monitor")

        assert_includes shell.commands, [ "bin/rails", "generate", "source_monitor:install", "--mount-path=/admin/source_monitor" ]
      end
    end
  end
end
