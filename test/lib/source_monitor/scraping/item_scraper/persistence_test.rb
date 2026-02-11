# frozen_string_literal: true

require "test_helper"
require "source_monitor/scraping/item_scraper/persistence"

module SourceMonitor
  module Scraping
    class ItemScraper
      class PersistenceTest < ActiveSupport::TestCase
        test "persists successful adapter result and returns scraper result" do
          source = create_source!
          item = source.items.create!(
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex}",
            title: "Example"
          )

          started_at = Time.zone.parse("2025-10-10 12:00:00 UTC")
          travel_to started_at do
            adapter_result = SourceMonitor::Scrapers::Base::Result.new(
              status: :success,
              html: "<article>HTML</article>",
              content: "Body",
              metadata: { http_status: 200, extraction_strategy: "readability" }
            )

            persistence = SourceMonitor::Scraping::ItemScraper::Persistence.new(
              item:,
              source:,
              adapter_name: "readability"
            )

            result = persistence.persist_success(adapter_result:, started_at:)

            assert_equal :success, result.status
            assert_equal item, result.item
            assert result.log.present?
            assert_equal "Scrape completed via Readability", result.message

            item.reload
            assert_equal "success", item.scrape_status
            assert_equal "<article>HTML</article>", item.scraped_html
            assert_equal "Body", item.scraped_content

            log = SourceMonitor::ScrapeLog.where(item: item).order(:created_at).last
            assert_equal item, log.item
            assert_equal source, log.source
            assert log.success
            assert_equal "readability", log.scraper_adapter
            assert_equal 200, log.http_status
            assert_equal "readability", log.metadata["extraction_strategy"]
            assert_in_delta started_at + 0.seconds, item.scraped_at, 1.second
            assert_in_delta started_at + 0.seconds, log.completed_at, 1.second
          end
        end

        test "persists failure result when adapter raises" do
          source = create_source!
          item = source.items.create!(
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex}",
            title: "Example"
          )

          started_at = Time.zone.parse("2025-10-10 13:00:00 UTC")
          error = StandardError.new("boom")

          persistence = SourceMonitor::Scraping::ItemScraper::Persistence.new(
            item:,
            source:,
            adapter_name: "readability"
          )

          result = nil
          travel_to started_at do
            result = persistence.persist_failure(error:, started_at:)
          end

          assert_equal :failed, result.status
          assert_equal item, result.item
          assert result.failed?
          assert_includes result.message, "Scrape failed"

          item.reload
          assert_equal "failed", item.scrape_status
          assert_not_nil item.scraped_at

          log = SourceMonitor::ScrapeLog.where(item: item).order(:created_at).last
          refute log.success
          assert_equal "boom", log.error_message
          assert_equal "StandardError", log.error_class
          assert_equal "StandardError", log.metadata["error"]
          assert_equal "boom", log.metadata["message"]
        end
      end
    end
  end
end
