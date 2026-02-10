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
        source = create_source
        item = create_item(source:)

        SourceMonitor::Realtime.stub(:broadcast_item, ->(_item) { flunk("should not broadcast") }) do
          SourceMonitor::Scraping::State.mark_pending!(item, broadcast: false)
        end

        assert_equal "pending", item.reload.scrape_status
      end

      test "mark_processing sets processing and broadcasts" do
        source = create_source
        item = create_item(source:)

        broadcasted = false
        SourceMonitor::Realtime.stub(:broadcast_item, ->(broadcast_item) { broadcasted = broadcast_item == item }) do
          SourceMonitor::Scraping::State.mark_processing!(item)
        end

        item.reload
        assert_equal "processing", item.scrape_status
        assert broadcasted
      end

      test "clear_inflight resets status when in flight" do
        source = create_source
        item = create_item(source:)
        item.update!(scrape_status: "processing")

        SourceMonitor::Scraping::State.clear_inflight!(item)

        assert_nil item.reload.scrape_status
      end

      test "clear_inflight leaves status when not in flight" do
        source = create_source
        item = create_item(source:)
        item.update!(scrape_status: "success")

        SourceMonitor::Scraping::State.clear_inflight!(item)

        assert_equal "success", item.reload.scrape_status
      end

      private

      def create_source
        create_source!(scraping_enabled: true, auto_scrape: true)
      end

      def create_item(source:)
        SourceMonitor::Item.create!(
          source: source,
          guid: SecureRandom.uuid,
          url: "https://example.com/#{SecureRandom.hex}",
          title: "Item"
        )
      end
    end
  end
end
