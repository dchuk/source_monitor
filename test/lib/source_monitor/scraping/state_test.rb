# frozen_string_literal: true

require "test_helper"
require "securerandom"

module SourceMonitor
  module Scraping
    class StateTest < ActiveSupport::TestCase
      setup do
        clean_source_monitor_tables!
      end

      test "mark_pending sets the item to pending without broadcast" do
        source = create_source!(scraping_enabled: true, auto_scrape: true)
        item = create_item!(source:)

        SourceMonitor::Realtime.stub(:broadcast_item, ->(_item) { flunk("should not broadcast") }) do
          SourceMonitor::Scraping::State.mark_pending!(item, broadcast: false)
        end

        assert_equal "pending", item.reload.scrape_status
      end

      test "mark_processing sets processing and broadcasts" do
        source = create_source!(scraping_enabled: true, auto_scrape: true)
        item = create_item!(source:)

        broadcasted = false
        SourceMonitor::Realtime.stub(:broadcast_item, ->(broadcast_item) { broadcasted = broadcast_item == item }) do
          SourceMonitor::Scraping::State.mark_processing!(item)
        end

        item.reload
        assert_equal "processing", item.scrape_status
        assert broadcasted
      end

      test "clear_inflight resets status when in flight" do
        source = create_source!(scraping_enabled: true, auto_scrape: true)
        item = create_item!(source:)
        item.update!(scrape_status: "processing")

        SourceMonitor::Scraping::State.clear_inflight!(item)

        assert_nil item.reload.scrape_status
      end

      test "clear_inflight leaves status when not in flight" do
        source = create_source!(scraping_enabled: true, auto_scrape: true)
        item = create_item!(source:)
        item.update!(scrape_status: "success")

        SourceMonitor::Scraping::State.clear_inflight!(item)

        assert_equal "success", item.reload.scrape_status
      end

      test "broadcast_item swallows errors and logs them" do
        source = create_source!(scraping_enabled: true, auto_scrape: true)
        item = create_item!(source:)

        logged_messages = []
        mock_logger = Object.new
        mock_logger.define_singleton_method(:warn) { |msg| logged_messages << msg }

        SourceMonitor::Realtime.stub(:broadcast_item, ->(_item) { raise StandardError, "broadcast error" }) do
          Rails.stub(:logger, mock_logger) do
            SourceMonitor::Scraping::State.mark_processing!(item)
          end
        end

        assert_equal "processing", item.reload.scrape_status
        assert_equal 1, logged_messages.size
        assert_includes logged_messages.first, "Broadcast failed"
        assert_includes logged_messages.first, "broadcast error"
      end

      test "sequential state transitions do not raise with_lock dirty attribute error" do
        source = create_source!(scraping_enabled: true, auto_scrape: true)
        item = create_item!(source:)

        # Simulate Runner flow: mark_processing! then clear_inflight! on the same
        # in-memory item instance. Before the fix, assign_attributes left dirty
        # state that caused Rails 8.1.2's with_lock guard to raise RuntimeError.
        assert_nothing_raised do
          SourceMonitor::Scraping::State.mark_processing!(item)
          SourceMonitor::Scraping::State.clear_inflight!(item)
        end

        assert_nil item.reload.scrape_status
      end

      test "mark_failed then clear_inflight does not raise on same instance" do
        source = create_source!(scraping_enabled: true, auto_scrape: true)
        item = create_item!(source:)

        assert_nothing_raised do
          SourceMonitor::Scraping::State.mark_processing!(item)
          SourceMonitor::Scraping::State.mark_failed!(item)
          SourceMonitor::Scraping::State.clear_inflight!(item)
        end

        # failed is not an in-flight status, so clear_inflight! should leave it
        assert_equal "failed", item.reload.scrape_status
      end

      private
    end
  end
end
