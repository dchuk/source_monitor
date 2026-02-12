# frozen_string_literal: true

module SourceMonitor
  module Setup
    module Verification
      class SolidQueueVerifier
        DEFAULT_HEARTBEAT_THRESHOLD = 2.minutes

        def initialize(process_relation: default_process_relation, connection: default_connection, clock: -> { Time.current })
          @process_relation = process_relation
          @connection = connection
          @clock = clock
        end

        def call
          return missing_gem_result unless process_relation
          return missing_tables_result unless tables_present?

          recent = recent_workers?

          if recent
            ok_result("Solid Queue workers are reporting heartbeats")
          else
            warning_result("No Solid Queue workers have reported in the last #{DEFAULT_HEARTBEAT_THRESHOLD.inspect}", "Start a Solid Queue worker with `bin/rails solid_queue:start` or add `jobs: bundle exec rake solid_queue:start` to Procfile.dev and run `bin/dev`")
          end
        rescue StandardError => e
          error_result("Solid Queue verification failed: #{e.message}", "Verify Solid Queue migrations are up to date and workers can access the database")
        end

        private

        attr_reader :process_relation, :connection, :clock

        def default_process_relation
          SolidQueue::Process if defined?(SolidQueue::Process)
        end

        def default_connection
          SolidQueue::Process.connection if defined?(SolidQueue::Process)
        rescue StandardError
          nil
        end

        def tables_present?
          return false unless connection

          connection.table_exists?(process_relation.table_name)
        end

        def recent_workers?
          cutoff = clock.call - DEFAULT_HEARTBEAT_THRESHOLD
          process_relation.where("last_heartbeat_at >= ?", cutoff).exists?
        end

        def missing_gem_result
          error_result("Solid Queue gem is not available", "Add `solid_queue` to your Gemfile and bundle install")
        end

        def missing_tables_result
          error_result("Solid Queue tables are missing", "Run `rails solid_queue:install` or copy the engine's Solid Queue migration")
        end

        def ok_result(details)
          Result.new(key: :solid_queue, name: "Solid Queue", status: :ok, details: details)
        end

        def warning_result(details, remediation)
          Result.new(key: :solid_queue, name: "Solid Queue", status: :warning, details: details, remediation: remediation)
        end

        def error_result(details, remediation)
          Result.new(key: :solid_queue, name: "Solid Queue", status: :error, details: details, remediation: remediation)
        end
      end
    end
  end
end
