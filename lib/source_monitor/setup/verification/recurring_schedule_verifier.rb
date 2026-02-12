# frozen_string_literal: true

module SourceMonitor
  module Setup
    module Verification
      class RecurringScheduleVerifier
        SOURCE_MONITOR_KEY_PREFIX = "source_monitor_"
        SOURCE_MONITOR_NAMESPACE = "SourceMonitor::"

        def initialize(task_relation: default_task_relation, connection: default_connection)
          @task_relation = task_relation
          @connection = connection
        end

        def call
          return missing_gem_result unless task_relation
          return missing_tables_result unless tables_present?

          tasks = all_tasks
          sm_tasks = source_monitor_tasks(tasks)

          if sm_tasks.any?
            ok_result("#{sm_tasks.size} SourceMonitor recurring task(s) registered")
          elsif tasks.any?
            warning_result(
              "Recurring tasks exist but none belong to SourceMonitor",
              "Add SourceMonitor entries to config/recurring.yml and ensure the dispatcher has `recurring_schedule: config/recurring.yml`"
            )
          else
            warning_result(
              "No recurring tasks are registered with Solid Queue",
              "Configure a dispatcher with `recurring_schedule: config/recurring.yml` in config/queue.yml and ensure recurring.yml contains SourceMonitor task entries"
            )
          end
        rescue StandardError => e
          error_result(
            "Recurring schedule verification failed: #{e.message}",
            "Verify Solid Queue migrations are up to date and the dispatcher is configured with recurring_schedule"
          )
        end

        private

        attr_reader :task_relation, :connection

        def default_task_relation
          SolidQueue::RecurringTask if defined?(SolidQueue::RecurringTask)
        end

        def default_connection
          SolidQueue::RecurringTask.connection if defined?(SolidQueue::RecurringTask)
        rescue StandardError
          nil
        end

        def tables_present?
          return false unless connection

          connection.table_exists?(task_relation.table_name)
        end

        def all_tasks
          task_relation.all.to_a
        end

        def source_monitor_tasks(tasks)
          tasks.select do |task|
            task.key.start_with?(SOURCE_MONITOR_KEY_PREFIX) ||
              task.class_name.to_s.start_with?(SOURCE_MONITOR_NAMESPACE) ||
              task.command.to_s.include?(SOURCE_MONITOR_NAMESPACE)
          end
        end

        def missing_gem_result
          error_result(
            "Solid Queue gem is not available",
            "Add `solid_queue` to your Gemfile and bundle install"
          )
        end

        def missing_tables_result
          error_result(
            "Solid Queue recurring tasks table is missing",
            "Run `rails solid_queue:install` or copy the engine's Solid Queue migration"
          )
        end

        def ok_result(details)
          Result.new(key: :recurring_schedule, name: "Recurring Schedule", status: :ok, details: details)
        end

        def warning_result(details, remediation)
          Result.new(key: :recurring_schedule, name: "Recurring Schedule", status: :warning, details: details, remediation: remediation)
        end

        def error_result(details, remediation)
          Result.new(key: :recurring_schedule, name: "Recurring Schedule", status: :error, details: details, remediation: remediation)
        end
      end
    end
  end
end
