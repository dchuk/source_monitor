# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "source_monitor/setup/verification/pending_migrations_verifier"

module SourceMonitor
  module Setup
    module Verification
      class PendingMigrationsVerifierTest < ActiveSupport::TestCase
        class FakeMigrationContext
          def initialize(needs_migration:)
            @needs_migration = needs_migration
          end

          def needs_migration?
            @needs_migration
          end
        end

        test "returns ok when all engine migrations are present and none pending" do
          Dir.mktmpdir do |engine_dir|
            Dir.mktmpdir do |host_dir|
              File.write(File.join(engine_dir, "20241008120000_create_source_monitor_sources.rb"), "")
              File.write(File.join(engine_dir, "20241008121000_create_source_monitor_items.rb"), "")

              File.write(File.join(host_dir, "20250101000000_create_source_monitor_sources.rb"), "")
              File.write(File.join(host_dir, "20250101000001_create_source_monitor_items.rb"), "")

              context = FakeMigrationContext.new(needs_migration: false)
              verifier = PendingMigrationsVerifier.new(
                engine_migrations_path: engine_dir,
                host_migrations_path: host_dir,
                migration_context: context
              )

              result = verifier.call

              assert_equal :ok, result.status
              assert_equal :pending_migrations, result.key
              assert_match(/present and up to date/, result.details)
            end
          end
        end

        test "warns when engine migrations are missing from host" do
          Dir.mktmpdir do |engine_dir|
            Dir.mktmpdir do |host_dir|
              File.write(File.join(engine_dir, "20241008120000_create_source_monitor_sources.rb"), "")
              File.write(File.join(engine_dir, "20241008121000_create_source_monitor_items.rb"), "")

              File.write(File.join(host_dir, "20250101000000_create_source_monitor_sources.rb"), "")

              context = FakeMigrationContext.new(needs_migration: false)
              verifier = PendingMigrationsVerifier.new(
                engine_migrations_path: engine_dir,
                host_migrations_path: host_dir,
                migration_context: context
              )

              result = verifier.call

              assert_equal :warning, result.status
              assert_match(/1 SourceMonitor migration/, result.details)
              assert_match(/create_source_monitor_items/, result.details)
              assert_match(/source_monitor:upgrade/, result.remediation)
            end
          end
        end

        test "warns when migrations are pending" do
          Dir.mktmpdir do |engine_dir|
            Dir.mktmpdir do |host_dir|
              File.write(File.join(engine_dir, "20241008120000_create_source_monitor_sources.rb"), "")

              File.write(File.join(host_dir, "20250101000000_create_source_monitor_sources.rb"), "")

              context = FakeMigrationContext.new(needs_migration: true)
              verifier = PendingMigrationsVerifier.new(
                engine_migrations_path: engine_dir,
                host_migrations_path: host_dir,
                migration_context: context
              )

              result = verifier.call

              assert_equal :warning, result.status
              assert_match(/pending/, result.details)
              assert_match(/db:migrate/, result.remediation)
            end
          end
        end

        test "returns ok when host migrations have .source_monitor engine suffix" do
          Dir.mktmpdir do |engine_dir|
            Dir.mktmpdir do |host_dir|
              File.write(File.join(engine_dir, "20241008120000_create_source_monitor_sources.rb"), "")
              File.write(File.join(engine_dir, "20241008121000_create_source_monitor_items.rb"), "")

              File.write(File.join(host_dir, "20250101000000_create_source_monitor_sources.source_monitor.rb"), "")
              File.write(File.join(host_dir, "20250101000001_create_source_monitor_items.source_monitor.rb"), "")

              context = FakeMigrationContext.new(needs_migration: false)
              verifier = PendingMigrationsVerifier.new(
                engine_migrations_path: engine_dir,
                host_migrations_path: host_dir,
                migration_context: context
              )

              result = verifier.call

              assert_equal :ok, result.status
              assert_match(/present and up to date/, result.details)
            end
          end
        end

        test "ignores non-source-monitor engine migrations" do
          Dir.mktmpdir do |engine_dir|
            Dir.mktmpdir do |host_dir|
              File.write(File.join(engine_dir, "20251010160000_create_solid_cable_messages.rb"), "")
              File.write(File.join(engine_dir, "20240101000000_create_solid_queue_tables.rb"), "")

              context = FakeMigrationContext.new(needs_migration: false)
              verifier = PendingMigrationsVerifier.new(
                engine_migrations_path: engine_dir,
                host_migrations_path: host_dir,
                migration_context: context
              )

              result = verifier.call

              assert_equal :ok, result.status
              assert_match(/No SourceMonitor engine migrations/, result.details)
            end
          end
        end

        test "rescues unexpected failures" do
          Dir.mktmpdir do |engine_dir|
            Dir.mktmpdir do |host_dir|
              File.write(File.join(engine_dir, "20241008120000_create_source_monitor_sources.rb"), "")
              File.write(File.join(host_dir, "20250101000000_create_source_monitor_sources.rb"), "")

              bad_context = Class.new do
                def needs_migration?
                  raise "connection exploded"
                end
              end.new

              verifier = PendingMigrationsVerifier.new(
                engine_migrations_path: engine_dir,
                host_migrations_path: host_dir,
                migration_context: bad_context
              )

              result = verifier.call

              assert_equal :error, result.status
              assert_match(/verification failed/, result.details)
              assert_match(/connection exploded/, result.details)
              assert_match(/database connectivity/, result.remediation)
            end
          end
        end
      end
    end
  end
end
