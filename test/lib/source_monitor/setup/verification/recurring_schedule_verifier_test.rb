# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Setup
    module Verification
      class RecurringScheduleVerifierTest < ActiveSupport::TestCase
        FakeTask = Struct.new(:key, :class_name, :command, keyword_init: true)

        class FakeTaskRelation
          attr_reader :table_name

          def initialize(tasks, table_name: "solid_queue_recurring_tasks")
            @tasks = tasks
            @table_name = table_name
          end

          def all
            self
          end

          def to_a
            @tasks
          end
        end

        class FakeConnection
          def initialize(tables: [])
            @tables = tables
          end

          def table_exists?(name)
            @tables.include?(name)
          end
        end

        test "returns ok when source monitor recurring tasks are registered" do
          tasks = [
            FakeTask.new(key: "source_monitor_schedule_fetches", class_name: "SourceMonitor::ScheduleFetchesJob", command: nil),
            FakeTask.new(key: "source_monitor_item_cleanup", class_name: "SourceMonitor::ItemCleanupJob", command: nil)
          ]
          relation = FakeTaskRelation.new(tasks)
          connection = FakeConnection.new(tables: [ "solid_queue_recurring_tasks" ])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :ok, result.status
          assert_match(/2 SourceMonitor recurring task/, result.details)
        end

        test "returns ok when source monitor tasks detected by command" do
          tasks = [
            FakeTask.new(key: "source_monitor_schedule_scrapes", class_name: nil, command: "SourceMonitor::Scraping::Scheduler.run(limit: 100)")
          ]
          relation = FakeTaskRelation.new(tasks)
          connection = FakeConnection.new(tables: [ "solid_queue_recurring_tasks" ])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :ok, result.status
        end

        test "warns when tasks exist but none belong to source monitor" do
          tasks = [
            FakeTask.new(key: "other_app_cleanup", class_name: "OtherApp::CleanupJob", command: nil)
          ]
          relation = FakeTaskRelation.new(tasks)
          connection = FakeConnection.new(tables: [ "solid_queue_recurring_tasks" ])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :warning, result.status
          assert_match(/none belong to SourceMonitor/, result.details)
          assert_match(/recurring\.yml/, result.remediation)
        end

        test "warns when no recurring tasks are registered" do
          relation = FakeTaskRelation.new([])
          connection = FakeConnection.new(tables: [ "solid_queue_recurring_tasks" ])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :warning, result.status
          assert_match(/No recurring tasks are registered/, result.details)
          assert_match(/recurring_schedule/, result.remediation)
        end

        test "errors when solid queue gem is missing" do
          result = RecurringScheduleVerifier.new(task_relation: nil, connection: nil).call

          assert_equal :error, result.status
          assert_match(/gem is not available/, result.details)
        end

        test "errors when recurring tasks table is missing" do
          relation = FakeTaskRelation.new([], table_name: "solid_queue_recurring_tasks")
          connection = FakeConnection.new(tables: [])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :error, result.status
          assert_match(/table is missing/, result.details)
        end

        test "rescues unexpected failures and reports remediation" do
          relation = Class.new do
            def table_name = "solid_queue_recurring_tasks"
            def all = raise "boom"
          end.new
          connection = FakeConnection.new(tables: [ "solid_queue_recurring_tasks" ])

          result = RecurringScheduleVerifier.new(task_relation: relation, connection: connection).call

          assert_equal :error, result.status
          assert_match(/verification failed/i, result.details)
          assert_match(/dispatcher/, result.remediation)
        end
      end
    end
  end
end
