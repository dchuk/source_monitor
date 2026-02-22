# frozen_string_literal: true

require "test_helper"
require "securerandom"

module SourceMonitor
  module Scraping
    class EnqueuerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        clear_enqueued_jobs
        clean_source_monitor_tables!
      end

      test "enqueues scrape job and marks item pending" do
        source = create_source(scraping_enabled: true)
        item = create_item(source:)

        result = nil

        assert_enqueued_with(job: SourceMonitor::ScrapeItemJob, args: [ item.id ]) do
          result = Enqueuer.enqueue(item: item, reason: :manual)
        end

        assert result.enqueued?, "expected enqueue result to signal success"
        assert_equal "pending", item.reload.scrape_status
      end

      test "does not enqueue when scraping is disabled" do
        source = create_source(scraping_enabled: false)
        item = create_item(source:)

        result = Enqueuer.enqueue(item: item, reason: :manual)

        assert result.failure?
        assert_equal :scraping_disabled, result.status
        assert_equal "Scraping is disabled for this source.", result.message
        assert_enqueued_jobs 0
        assert_nil item.reload.scrape_status
      end

      test "deduplicates when item already pending or processing" do
        source = create_source(scraping_enabled: true)
        item = create_item(source:, scrape_status: "pending")

        result = Enqueuer.enqueue(item: item, reason: :manual)

        assert result.already_enqueued?, "expected deduplication to report already enqueued"
        assert_equal "Scrape already in progress for this item.", result.message
        assert_enqueued_jobs 0

        item.update!(scrape_status: "processing")
        second_result = Enqueuer.enqueue(item: item, reason: :manual)

        assert second_result.already_enqueued?
        assert_enqueued_jobs 0
      end

      test "respects automatic scraping configuration" do
        source = create_source(scraping_enabled: true, auto_scrape: false)
        item = create_item(source:)

        result = Enqueuer.enqueue(item: item, reason: :auto)

        assert result.failure?
        assert_equal :auto_scrape_disabled, result.status
        assert_enqueued_jobs 0
      end

      test "enforces per-source in-flight rate limit" do
        source = create_source(scraping_enabled: true)
        create_item(source:, scrape_status: "pending")
        item = create_item(source:)

        SourceMonitor.configure do |config|
          config.scraping.max_in_flight_per_source = 1
        end

        result = Enqueuer.enqueue(item: item, reason: :manual)

        assert result.failure?
        assert_equal :rate_limited, result.status
        assert_match(/scraping queue is full/i, result.message)
        assert_enqueued_jobs 0
        assert_nil item.reload.scrape_status
      end

      test "does not rate-limit when max_in_flight_per_source is nil (default)" do
        source = create_source(scraping_enabled: true)
        30.times { create_item(source:, scrape_status: "pending") }
        item = create_item(source:)

        # Default is nil -- no limit should apply even with 30 in-flight items
        assert_nil SourceMonitor.config.scraping.max_in_flight_per_source

        result = Enqueuer.enqueue(item: item, reason: :manual)

        assert result.enqueued?, "expected enqueue to succeed with nil limit, got #{result.status}"
      end

      # -- Time-based rate limiting tests --

      test "allows scrape when no prior scrape exists" do
        source = create_source(scraping_enabled: true)
        item = create_item(source:)

        SourceMonitor.configure { |c| c.scraping.min_scrape_interval = 60.0 }

        result = Enqueuer.enqueue(item: item, reason: :manual)

        assert result.enqueued?, "expected enqueue when no prior scrape, got #{result.status}"
      end

      test "allows scrape when elapsed time exceeds interval" do
        source = create_source(scraping_enabled: true)
        item = create_item(source:)

        SourceMonitor.configure { |c| c.scraping.min_scrape_interval = 5.0 }

        # Create a scrape log from 10 seconds ago
        create_scrape_log(source:, item:, started_at: 10.seconds.ago)

        result = Enqueuer.enqueue(item: item, reason: :manual)

        assert result.enqueued?, "expected enqueue when elapsed > interval, got #{result.status}"
      end

      test "returns deferred status when elapsed time is less than interval" do
        source = create_source(scraping_enabled: true)
        item = create_item(source:)

        SourceMonitor.configure { |c| c.scraping.min_scrape_interval = 60.0 }

        # Create a scrape log from 5 seconds ago
        create_scrape_log(source:, item:, started_at: 5.seconds.ago)

        result = Enqueuer.enqueue(item: item, reason: :manual)

        assert result.deferred?, "expected deferred result, got #{result.status}"
        assert_match(/deferred/i, result.message)
      end

      test "per-source min_scrape_interval overrides global setting" do
        source = create_source(scraping_enabled: true)
        source.update_columns(min_scrape_interval: 120.0)
        item = create_item(source:)

        # Global is 5 seconds, but source overrides to 120 seconds
        SourceMonitor.configure { |c| c.scraping.min_scrape_interval = 5.0 }

        # Scrape log from 10 seconds ago -- past global but within source override
        create_scrape_log(source:, item:, started_at: 10.seconds.ago)

        result = Enqueuer.enqueue(item: item, reason: :manual)

        assert result.deferred?, "expected per-source override to defer, got #{result.status}"
      end

      test "nil or zero interval disables time rate limiting" do
        source = create_source(scraping_enabled: true)
        item = create_item(source:)

        # Set global interval to nil
        SourceMonitor.configure { |c| c.scraping.min_scrape_interval = nil }

        # Scrape log from just now
        create_scrape_log(source:, item:, started_at: Time.current)

        result = Enqueuer.enqueue(item: item, reason: :manual)

        assert result.enqueued?, "expected nil interval to disable limiting, got #{result.status}"

        # Also test zero
        SourceMonitor.configure { |c| c.scraping.min_scrape_interval = 0 }

        item2 = create_item(source:)
        result2 = Enqueuer.enqueue(item: item2, reason: :manual)

        assert result2.enqueued?, "expected zero interval to disable limiting, got #{result2.status}"
      end

      test "deferred result re-enqueues job with delay" do
        source = create_source(scraping_enabled: true)
        item = create_item(source:)

        SourceMonitor.configure { |c| c.scraping.min_scrape_interval = 60.0 }

        # Scrape log from 5 seconds ago -- 55 seconds remaining
        create_scrape_log(source:, item:, started_at: 5.seconds.ago)

        assert_enqueued_jobs 0

        result = Enqueuer.enqueue(item: item, reason: :manual)

        assert result.deferred?
        assert_enqueued_jobs 1

        enqueued = queue_adapter.enqueued_jobs.last
        assert enqueued[:at].present?, "expected job to be scheduled with delay"
      end

      private

      def create_source(scraping_enabled:, auto_scrape: false)
        create_source!(
          scraping_enabled: scraping_enabled,
          auto_scrape: auto_scrape
        )
      end

      def create_item(source:, scrape_status: nil)
        SourceMonitor::Item.create!(
          source: source,
          guid: SecureRandom.uuid,
          url: "https://example.com/#{SecureRandom.hex}",
          title: "Example Item",
          scrape_status: scrape_status
        )
      end

      def create_scrape_log(source:, item:, started_at:)
        SourceMonitor::ScrapeLog.create!(
          source: source,
          item: item,
          started_at: started_at,
          scraper_adapter: "readability"
        )
      end
    end
  end
end
