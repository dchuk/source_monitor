# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module SourceMonitor
  module Setup
    class NodeInstallerTest < ActiveSupport::TestCase
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

      test "skips when package.json missing" do
        Dir.mktmpdir do |dir|
          installer = NodeInstaller.new(root: dir, shell: FakeShell.new)
          refute installer.install_if_needed
        end
      end

      test "runs npm install when package.json present" do
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, "package.json"), "{}")
          shell = FakeShell.new
          installer = NodeInstaller.new(root: dir, shell: shell)

          assert installer.install_if_needed
          assert_equal [ [ "npm", "install" ] ], shell.commands
        end
      end
    end
  end
end
