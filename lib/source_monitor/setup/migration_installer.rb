# frozen_string_literal: true

require "fileutils"
require "pathname"

module SourceMonitor
  module Setup
    class MigrationInstaller
      SOLID_QUEUE_PATTERN = "*_create_solid_queue_tables.rb"

      def initialize(shell: ShellRunner.new, migrations_path: "db/migrate")
        @shell = shell
        @migrations_path = Pathname.new(migrations_path)
      end

      def install
        copy_migrations
        deduplicate_solid_queue
        run_migrations
      end

      private

      attr_reader :shell, :migrations_path

      def copy_migrations
        shell.run("bin/rails", "railties:install:migrations", "FROM=source_monitor")
      end

      def deduplicate_solid_queue
        files = Dir[migrations_path.join(SOLID_QUEUE_PATTERN).to_s].sort
        return if files.size <= 1

        files[1..].each { |path| FileUtils.rm_f(path) }
      end

      def run_migrations
        shell.run("bin/rails", "db:migrate")
      end
    end
  end
end
