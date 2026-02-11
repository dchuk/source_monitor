# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    class BundleInstallerTest < ActiveSupport::TestCase
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

      test "invokes bundle install" do
        shell = FakeShell.new
        installer = BundleInstaller.new(shell: shell)

        installer.install

        assert_equal [ [ "bundle", "install" ] ], shell.commands
      end
    end
  end
end
