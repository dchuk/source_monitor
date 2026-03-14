# frozen_string_literal: true

require "test_helper"
require "source_monitor/fetching/completion/event_publisher"

module SourceMonitor
  module Fetching
    module Completion
      class EventPublisherTest < ActiveSupport::TestCase
        setup do
          @source = create_source!
        end

        test "returns Result with :published status on success" do
          spy_dispatcher = Class.new do
            define_method(:after_fetch_completed) { |**| nil }
          end.new

          handler = EventPublisher.new(dispatcher: spy_dispatcher)
          result = handler.call(source: @source, result: fetched_result)

          assert_instance_of EventPublisher::Result, result
          assert_equal :published, result.status
          assert_nil result.error
          assert result.success?
        end

        test "returns Result with :failed status on error" do
          failing_dispatcher = Class.new do
            define_method(:after_fetch_completed) { |**| raise StandardError, "dispatch boom" }
          end.new

          handler = EventPublisher.new(dispatcher: failing_dispatcher)
          result = handler.call(source: @source, result: fetched_result)

          assert_instance_of EventPublisher::Result, result
          assert_equal :failed, result.status
          assert_equal "dispatch boom", result.error.message
          refute result.success?
        end

        private

        def fetched_result
          SourceMonitor::Fetching::FeedFetcher::Result.new(status: :fetched)
        end
      end
    end
  end
end
