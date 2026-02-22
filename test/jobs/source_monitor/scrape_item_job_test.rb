# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "minitest/mock"

module SourceMonitor
  class ScrapeItemJobTest < ActiveJob::TestCase
    test "performs scraping via item scraper and records a log" do
      source = create_source(scraping_enabled: true)
      item = create_item(source:)

      result = SourceMonitor::Scrapers::Base::Result.new(
        status: :success,
        html: "<article><p>Scraped HTML</p></article>",
        content: "Scraped body",
        metadata: { http_status: 200, extraction_strategy: "readability" }
      )

      SourceMonitor::Scrapers::Readability.stub(:call, result) do
        assert_difference("SourceMonitor::ScrapeLog.count", 1) do
          SourceMonitor::ScrapeItemJob.perform_now(item.id)
        end
      end

      item.reload
      assert_equal "success", item.scrape_status
      assert_equal "Scraped body", item.scraped_content
      assert item.scraped_at.present?
    end

    test "skips scraping when the source has been disabled" do
      source = create_source(scraping_enabled: false)
      item = create_item(source:)

      assert_no_changes -> { SourceMonitor::ScrapeLog.count } do
        SourceMonitor::ScrapeItemJob.perform_now(item.id)
      end

      assert_nil item.reload.scrape_status
    end

    test "marks item failed and clears processing when scraper raises unexpectedly" do
      source = create_source(scraping_enabled: true)
      item = create_item(source:)

      fake_scraper = Class.new do
        def call
          raise StandardError, "boom"
        end
      end

      SourceMonitor::Scraping::ItemScraper.stub(:new, ->(**_args) { fake_scraper.new }) do
        assert_raises(StandardError) do
          SourceMonitor::ScrapeItemJob.perform_now(item.id)
        end
      end

      item.reload
      assert_equal "failed", item.scrape_status
      assert item.scraped_at.present?
    end

    # -- Time-based rate limiting tests --

    test "performs scrape when not rate-limited by time" do
      source = create_source(scraping_enabled: true)
      item = create_item(source:)

      SourceMonitor.configure { |c| c.scraping.min_scrape_interval = 5.0 }

      # Scrape log from 10 seconds ago -- past interval
      create_scrape_log(source:, item:, started_at: 10.seconds.ago)

      result = SourceMonitor::Scrapers::Base::Result.new(
        status: :success,
        html: "<p>Content</p>",
        content: "Content",
        metadata: { http_status: 200, extraction_strategy: "readability" }
      )

      SourceMonitor::Scrapers::Readability.stub(:call, result) do
        assert_difference("SourceMonitor::ScrapeLog.count", 1) do
          SourceMonitor::ScrapeItemJob.perform_now(item.id)
        end
      end

      assert_equal "success", item.reload.scrape_status
    end

    test "re-enqueues with delay when rate-limited by time" do
      source = create_source(scraping_enabled: true)
      item = create_item(source:)

      SourceMonitor.configure { |c| c.scraping.min_scrape_interval = 60.0 }

      # Scrape log from 5 seconds ago -- well within interval
      create_scrape_log(source:, item:, started_at: 5.seconds.ago)

      assert_no_changes -> { SourceMonitor::ScrapeLog.count } do
        SourceMonitor::ScrapeItemJob.perform_now(item.id)
      end

      # Should have re-enqueued itself with a delay
      assert_enqueued_jobs 1
      enqueued = queue_adapter.enqueued_jobs.last
      assert enqueued[:at].present?, "expected job to be scheduled with delay"
    end

    test "clears in-flight state on time-based deferral" do
      source = create_source(scraping_enabled: true)
      item = create_item(source:)
      item.update_columns(scrape_status: "pending")

      SourceMonitor.configure { |c| c.scraping.min_scrape_interval = 60.0 }

      # Scrape log from just now
      create_scrape_log(source:, item:, started_at: Time.current)

      SourceMonitor::ScrapeItemJob.perform_now(item.id)

      # In-flight state should be cleared
      assert_nil item.reload.scrape_status
    end

    private

    def create_source(scraping_enabled:)
      create_source!(
        scraping_enabled: scraping_enabled,
        auto_scrape: true
      )
    end

    def create_item(source:)
      SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/#{SecureRandom.hex}",
        title: "Example Item"
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
