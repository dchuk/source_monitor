# frozen_string_literal: true

require "test_helper"
require "source_monitor/fetching/completion/retention_handler"

module SourceMonitor
  module Fetching
    module Completion
      class RetentionHandlerTest < ActiveSupport::TestCase
        setup do
          @source = create_source!
        end

        test "returns Result with :applied status on successful pruning" do
          pruner_result = SourceMonitor::Items::RetentionPruner::Result.new(
            removed_by_age: 2, removed_by_limit: 1, removed_total: 3
          )
          stub_pruner = ->(**) { pruner_result }

          handler = RetentionHandler.new(pruner: stub_pruner)
          result = handler.call(source: @source, result: fetched_result)

          assert_instance_of RetentionHandler::Result, result
          assert_equal :applied, result.status
          assert_equal 3, result.removed_total
          assert_nil result.error
          assert result.success?
        end

        test "returns Result with :failed status and error on StandardError" do
          failing_pruner = ->(**) { raise StandardError, "pruner boom" }

          handler = RetentionHandler.new(pruner: failing_pruner)
          result = handler.call(source: @source, result: fetched_result)

          assert_instance_of RetentionHandler::Result, result
          assert_equal :failed, result.status
          assert_equal "pruner boom", result.error.message
          refute result.success?
        end

        test "returns Result with :skipped when pruner returns zero removals" do
          pruner_result = SourceMonitor::Items::RetentionPruner::Result.new(
            removed_by_age: 0, removed_by_limit: 0, removed_total: 0
          )
          stub_pruner = ->(**) { pruner_result }

          handler = RetentionHandler.new(pruner: stub_pruner)
          result = handler.call(source: @source, result: fetched_result)

          assert_instance_of RetentionHandler::Result, result
          assert_equal :applied, result.status
          assert_equal 0, result.removed_total
          assert result.success?
        end

        private

        def fetched_result
          SourceMonitor::Fetching::FeedFetcher::Result.new(status: :fetched)
        end
      end
    end
  end
end
