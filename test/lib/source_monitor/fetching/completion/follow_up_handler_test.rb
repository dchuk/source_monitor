# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "source_monitor/fetching/completion/follow_up_handler"

module SourceMonitor
  module Fetching
    module Completion
      class FollowUpHandlerTest < ActiveSupport::TestCase
        include ActiveJob::TestHelper

        setup { clear_enqueued_jobs }

        test "single enqueue failure does not prevent other items from being enqueued" do
          source = create_source!(scraping_enabled: true, auto_scrape: true)
          item1 = SourceMonitor::Item.create!(
            source: source,
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex}",
            title: "Item 1"
          )
          item2 = SourceMonitor::Item.create!(
            source: source,
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex}",
            title: "Item 2"
          )

          processing = SourceMonitor::Fetching::FeedFetcher::EntryProcessingResult.new(
            created: 2,
            updated: 0,
            failed: 0,
            items: [ item1, item2 ],
            errors: [],
            created_items: [ item1, item2 ],
            updated_items: []
          )
          result = SourceMonitor::Fetching::FeedFetcher::Result.new(
            status: :fetched,
            item_processing: processing
          )

          call_count = 0
          failing_enqueuer = Class.new do
            define_singleton_method(:enqueue) do |item:, **|
              call_count += 1
              raise StandardError, "enqueue boom" if call_count == 1
            end
          end

          handler = FollowUpHandler.new(enqueuer_class: failing_enqueuer)
          handler.call(source:, result:)

          assert_equal 2, call_count, "Both items should have had enqueue attempted"
        end

        test "returns Result with :applied status and enqueued_count on success" do
          source = create_source!(scraping_enabled: true, auto_scrape: true)
          item = SourceMonitor::Item.create!(
            source: source,
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex}",
            title: "Item 1"
          )

          processing = SourceMonitor::Fetching::FeedFetcher::EntryProcessingResult.new(
            created: 1, updated: 0, failed: 0,
            items: [ item ], errors: [],
            created_items: [ item ], updated_items: []
          )
          result = SourceMonitor::Fetching::FeedFetcher::Result.new(
            status: :fetched, item_processing: processing
          )

          enqueue_count = 0
          counting_enqueuer = Class.new do
            define_singleton_method(:enqueue) do |**|
              enqueue_count += 1
            end
          end

          handler = FollowUpHandler.new(enqueuer_class: counting_enqueuer)
          handler_result = handler.call(source:, result:)

          assert_instance_of FollowUpHandler::Result, handler_result
          assert_equal :applied, handler_result.status
          assert_equal 1, handler_result.enqueued_count
          assert_empty handler_result.errors
          assert handler_result.success?
        end

        test "returns Result with :failed status on error" do
          source = create_source!(scraping_enabled: true, auto_scrape: true)
          item = SourceMonitor::Item.create!(
            source: source,
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex}",
            title: "Item 1"
          )

          processing = SourceMonitor::Fetching::FeedFetcher::EntryProcessingResult.new(
            created: 1, updated: 0, failed: 0,
            items: [ item ], errors: [],
            created_items: [ item ], updated_items: []
          )
          result = SourceMonitor::Fetching::FeedFetcher::Result.new(
            status: :fetched, item_processing: processing
          )

          always_failing_enqueuer = Class.new do
            define_singleton_method(:enqueue) do |**|
              raise StandardError, "always fails"
            end
          end

          handler = FollowUpHandler.new(enqueuer_class: always_failing_enqueuer)
          handler_result = handler.call(source:, result:)

          assert_instance_of FollowUpHandler::Result, handler_result
          assert_equal :applied, handler_result.status
          assert_equal 0, handler_result.enqueued_count
          assert_equal 1, handler_result.errors.size
          assert_match(/always fails/, handler_result.errors.first.message)
        end

        test "returns Result with :skipped when should not enqueue" do
          source = create_source!(scraping_enabled: false, auto_scrape: false)
          result = SourceMonitor::Fetching::FeedFetcher::Result.new(status: :fetched)

          handler = FollowUpHandler.new
          handler_result = handler.call(source:, result:)

          assert_instance_of FollowUpHandler::Result, handler_result
          assert_equal :skipped, handler_result.status
          assert_equal 0, handler_result.enqueued_count
          assert_empty handler_result.errors
          assert handler_result.success?
        end

        test "captures per-item errors in errors array" do
          source = create_source!(scraping_enabled: true, auto_scrape: true)
          item1 = SourceMonitor::Item.create!(
            source: source,
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex}",
            title: "Item 1"
          )
          item2 = SourceMonitor::Item.create!(
            source: source,
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex}",
            title: "Item 2"
          )

          processing = SourceMonitor::Fetching::FeedFetcher::EntryProcessingResult.new(
            created: 2, updated: 0, failed: 0,
            items: [ item1, item2 ], errors: [],
            created_items: [ item1, item2 ], updated_items: []
          )
          result = SourceMonitor::Fetching::FeedFetcher::Result.new(
            status: :fetched, item_processing: processing
          )

          call_count = 0
          partial_failing_enqueuer = Class.new do
            define_singleton_method(:enqueue) do |**|
              call_count += 1
              raise StandardError, "item 1 failed" if call_count == 1
            end
          end

          handler = FollowUpHandler.new(enqueuer_class: partial_failing_enqueuer)
          handler_result = handler.call(source:, result:)

          assert_equal :applied, handler_result.status
          assert_equal 1, handler_result.enqueued_count
          assert_equal 1, handler_result.errors.size
        end

        test "#call completes without raising even when all enqueues raise" do
          source = create_source!(scraping_enabled: true, auto_scrape: true)
          item = SourceMonitor::Item.create!(
            source: source,
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex}",
            title: "Item 1"
          )

          processing = SourceMonitor::Fetching::FeedFetcher::EntryProcessingResult.new(
            created: 1,
            updated: 0,
            failed: 0,
            items: [ item ],
            errors: [],
            created_items: [ item ],
            updated_items: []
          )
          result = SourceMonitor::Fetching::FeedFetcher::Result.new(
            status: :fetched,
            item_processing: processing
          )

          always_failing_enqueuer = Class.new do
            define_singleton_method(:enqueue) do |**|
              raise StandardError, "always fails"
            end
          end

          handler = FollowUpHandler.new(enqueuer_class: always_failing_enqueuer)

          assert_nothing_raised do
            handler.call(source:, result:)
          end
        end
      end
    end
  end
end
