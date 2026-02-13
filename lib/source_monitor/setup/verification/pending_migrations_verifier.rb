# frozen_string_literal: true

module SourceMonitor
  module Setup
    module Verification
      class PendingMigrationsVerifier
        MIGRATION_TIMESTAMP_PATTERN = /\A\d+_/

        def initialize(
          engine_migrations_path: default_engine_migrations_path,
          host_migrations_path: default_host_migrations_path,
          connection: default_connection
        )
          @engine_migrations_path = engine_migrations_path
          @host_migrations_path = host_migrations_path
          @connection = connection
        end

        def call
          engine_names = source_monitor_migration_names(engine_migrations_path)
          return ok_result("No SourceMonitor engine migrations found") if engine_names.empty?

          host_names = migration_names(host_migrations_path)
          missing = engine_names - host_names

          if missing.any?
            warning_result(
              "#{missing.size} SourceMonitor migration(s) not copied to host: #{missing.join(', ')}",
              "Run `bin/source_monitor upgrade` or `bin/rails railties:install:migrations FROM=source_monitor`"
            )
          elsif connection.migration_context.needs_migration?
            warning_result(
              "All SourceMonitor migrations are copied but some migrations are pending",
              "Run `bin/rails db:migrate` to apply pending migrations"
            )
          else
            ok_result("All SourceMonitor migrations are present and up to date")
          end
        rescue StandardError => e
          error_result(
            "Migration verification failed: #{e.message}",
            "Check database connectivity and migration file permissions"
          )
        end

        private

        attr_reader :engine_migrations_path, :host_migrations_path, :connection

        def default_engine_migrations_path
          SourceMonitor::Engine.root.join("db/migrate")
        end

        def default_host_migrations_path
          Rails.root.join("db/migrate")
        end

        def default_connection
          ActiveRecord::Base.connection
        end

        def source_monitor_migration_names(path)
          migration_names(path).select { |name| name.include?("source_monitor") }
        end

        def migration_names(path)
          return [] unless File.directory?(path.to_s)

          Dir.children(path.to_s)
            .select { |f| f.end_with?(".rb") }
            .map { |f| strip_timestamp(f) }
        end

        def strip_timestamp(filename)
          filename.sub(MIGRATION_TIMESTAMP_PATTERN, "").delete_suffix(".rb")
        end

        def ok_result(details)
          Result.new(key: :pending_migrations, name: "Pending Migrations", status: :ok, details: details)
        end

        def warning_result(details, remediation)
          Result.new(key: :pending_migrations, name: "Pending Migrations", status: :warning, details: details, remediation: remediation)
        end

        def error_result(details, remediation)
          Result.new(key: :pending_migrations, name: "Pending Migrations", status: :error, details: details, remediation: remediation)
        end
      end
    end
  end
end
