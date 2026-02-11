# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module SourceMonitor
  module Setup
    class MigrationInstallerTest < ActiveSupport::TestCase
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

      test "copies migrations, deduplicates solid queue, and runs migrate" do
        Dir.mktmpdir do |dir|
          migrate_dir = File.join(dir, "db/migrate")
          FileUtils.mkdir_p(migrate_dir)
          File.write(File.join(migrate_dir, "20240101000000_create_solid_queue_tables.rb"), "")
          File.write(File.join(migrate_dir, "20240202000000_create_solid_queue_tables.rb"), "")

          shell = FakeShell.new
          installer = MigrationInstaller.new(shell: shell, migrations_path: migrate_dir)

          installer.install

          expected_commands = [
            [ "bin/rails", "railties:install:migrations", "FROM=source_monitor" ],
            [ "bin/rails", "db:migrate" ]
          ]
          assert_equal expected_commands, shell.commands

          solid_queue_files = Dir[File.join(migrate_dir, "*_create_solid_queue_tables.rb")]
          assert_equal 1, solid_queue_files.size
        end
      end
    end
  end
end
