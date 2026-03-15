# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Scraping
    class RunnerTest < ActiveSupport::TestCase
      test "performs scraping and records log on success" do
        source = create_source!(scraping_enabled: true, auto_scrape: true)
        item = create_item!(source: source)

        result = SourceMonitor::Scrapers::Base::Result.new(
          status: :success,
          html: "<article><p>Scraped</p></article>",
          content: "Scraped body",
          metadata: { http_status: 200, extraction_strategy: "readability" }
        )

        SourceMonitor::Scrapers::Readability.stub(:call, result) do
          assert_difference("SourceMonitor::ScrapeLog.count", 1) do
            Runner.new(item).call
          end
        end

        item.reload
        assert_equal "success", item.scrape_status
        assert_equal "Scraped body", item.scraped_content
      end

      test "skips when scraping disabled on source" do
        source = create_source!(scraping_enabled: false, auto_scrape: true)
        item = create_item!(source: source)

        assert_no_changes -> { SourceMonitor::ScrapeLog.count } do
          Runner.new(item).call
        end

        assert_nil item.reload.scrape_status
      end

      test "marks item failed and re-raises when scraper raises" do
        source = create_source!(scraping_enabled: true, auto_scrape: true)
        item = create_item!(source: source)

        fake_scraper = Class.new do
          def call
            raise StandardError, "boom"
          end
        end

        SourceMonitor::Scraping::ItemScraper.stub(:new, ->(**_args) { fake_scraper.new }) do
          assert_raises(StandardError) do
            Runner.new(item).call
          end
        end

        item.reload
        assert_equal "failed", item.scrape_status
        assert item.scraped_at.present?
      end

      test "clears inflight state in ensure block" do
        source = create_source!(scraping_enabled: true, auto_scrape: true)
        item = create_item!(source: source)
        item.update_columns(scrape_status: "pending")

        result = SourceMonitor::Scrapers::Base::Result.new(
          status: :success,
          html: "<p>Content</p>",
          content: "Content",
          metadata: { http_status: 200, extraction_strategy: "readability" }
        )

        SourceMonitor::Scrapers::Readability.stub(:call, result) do
          Runner.new(item).call
        end

        # After successful scrape, status should be set by ItemScraper (success),
        # not cleared to nil by clear_inflight! (because it's no longer in-flight)
        item.reload
        assert_equal "success", item.scrape_status
      end
    end
  end
end
