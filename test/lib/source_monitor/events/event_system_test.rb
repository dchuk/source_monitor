# frozen_string_literal: true

require "test_helper"
require "securerandom"

module SourceMonitor
  class EventSystemTest < ActiveSupport::TestCase
    setup do
      SourceMonitor.reset_configuration!
      clean_source_monitor_tables!
    end

    teardown do
      SourceMonitor.reset_configuration!
    end

    test "after_item_created callbacks run for newly created items" do
      captured = []
      SourceMonitor.configure do |config|
        config.events.after_item_created { |event| captured << event }
      end

      source = build_source
      feed = Feedjira.parse(file_fixture("feeds/rss_sample.xml").read)
      fetcher = SourceMonitor::Fetching::FeedFetcher.new(source: source, jitter: ->(_) { 0 })

      fetcher.send(:process_feed_entries, feed)

      assert captured.any?, "expected after_item_created callbacks to be invoked"
      event = captured.first
      assert_kind_of SourceMonitor::Events::ItemCreatedEvent, event
      assert_equal source, event.source
      assert_equal :created, event.status
      assert event.created?
    end

    test "custom item processors run for each processed entry" do
      processed = []
      SourceMonitor.configure do |config|
        config.events.register_item_processor(lambda { |context| processed << context.status })
      end

      source = build_source
      feed = Feedjira.parse(file_fixture("feeds/rss_sample.xml").read)
      fetcher = SourceMonitor::Fetching::FeedFetcher.new(source: source, jitter: ->(_) { 0 })

      result = fetcher.send(:process_feed_entries, feed)

      assert result.created.positive?
      assert_equal result.created, processed.count
      assert processed.all? { |status| status == :created }
    end

    test "after_fetch_completed callbacks receive the fetch result" do
      captured = []
      SourceMonitor.configure do |config|
        config.events.after_fetch_completed { |event| captured << event }
      end

      source = build_source

      fetcher_class = Class.new do
        Result = SourceMonitor::Fetching::FeedFetcher::Result
        EntryProcessingResult = SourceMonitor::Fetching::FeedFetcher::EntryProcessingResult

        def initialize(source:)
          @source = source
        end

        def call
          EntryProcessingResult.new(
            created: 0,
            updated: 0,
            failed: 0,
            items: [],
            errors: [],
            created_items: [],
            updated_items: []
          ).then do |processing|
            Result.new(status: :fetched, feed: nil, response: nil, body: nil, error: nil, item_processing: processing)
          end
        end
      end

      runner = SourceMonitor::Fetching::FetchRunner.new(
        source: source,
        fetcher_class: fetcher_class,
        scrape_enqueuer_class: NullScrapeEnqueuer,
        scrape_job_class: NullScrapeJob,
        retention_pruner_class: NullRetentionPruner
      )

      runner.run

      assert captured.any?, "expected after_fetch_completed callbacks to be invoked"
      event = captured.first
      assert_kind_of SourceMonitor::Events::FetchCompletedEvent, event
      assert_equal source, event.source
      assert_equal :fetched, event.status
    end

    test "after_item_scraped callbacks include scrape results" do
      captured = []
      SourceMonitor.configure do |config|
        config.scrapers.register(:test_adapter, TestScraper)
        config.events.after_item_scraped { |event| captured << event }
      end

      source = build_source(scraper_adapter: "test_adapter")
      item = SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        title: "Example",
        url: "https://example.com/article",
        canonical_url: "https://example.com/article",
        content: "Sample"
      )

      result = SourceMonitor::Scraping::ItemScraper.new(item: item, source: source, adapter_name: "test_adapter").call

      assert result.success?
      assert captured.any?, "expected after_item_scraped callbacks to run"
      event = captured.first
      assert_kind_of SourceMonitor::Events::ItemScrapedEvent, event
      assert_equal item, event.item
      assert_equal :success, event.status
      assert event.success?
    end

    private

    def build_source(overrides = {})
      defaults = {
        name: "Sample Source",
        feed_url: "https://example.com/feed-#{SecureRandom.hex(4)}.xml",
        adaptive_fetching_enabled: true
      }

      create_source!(defaults.merge(overrides))
    end

    class NullScrapeEnqueuer
      def self.enqueue(*)
        # no-op
      end
    end

    class NullScrapeJob < ActiveJob::Base; end

    class NullRetentionPruner
      def self.call(*)
        # no-op
      end
    end

    class TestScraper < SourceMonitor::Scrapers::Base
      def call
        SourceMonitor::Scrapers::Base::Result.new(
          status: :success,
          html: "<html></html>",
          content: "body",
          metadata: { http_status: 200 }
        )
      end
    end
  end
end
