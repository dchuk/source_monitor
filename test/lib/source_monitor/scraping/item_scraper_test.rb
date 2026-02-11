# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Scraping
    class ItemScraperTest < ActiveSupport::TestCase
      setup do
        SourceMonitor.reset_configuration!
        clean_source_monitor_tables!
      end

      teardown do
        SourceMonitor.reset_configuration!
      end

      test "respects configured scraper adapters" do
        source = create_source!(
          name: "Custom Adapter Source",
          feed_url: "https://example.com/custom.xml",
          scraper_adapter: "custom"
        )

        item = source.items.create!(
          guid: "custom-1",
          url: "https://example.com/custom-1",
          title: "Custom Item"
        )

        SourceMonitor.configure do |config|
          config.scrapers.register(:custom, FakeAdapter)
        end

        result = SourceMonitor::Scraping::ItemScraper.new(item:, source:).call

        assert result.success?
        assert_equal :success, result.status
        assert_equal "<p>HTML</p>", item.scraped_html
        assert_equal "Body", item.scraped_content
        assert_equal 1, FakeAdapter.calls
      ensure
        FakeAdapter.reset!
      end

      class FakeAdapter < SourceMonitor::Scrapers::Base
        class << self
          def calls
            @calls ||= 0
          end

          def reset!
            @calls = 0
          end
        end

        def call
          self.class.instance_variable_set(:@calls, self.class.calls + 1)
          Result.new(
            status: :success,
            html: "<p>HTML</p>",
            content: "Body",
            metadata: { adapter: self.class.adapter_name, source_id: source.id, item_id: item.id }
          )
        end
      end
    end
  end
end
