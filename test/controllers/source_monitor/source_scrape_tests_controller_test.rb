# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class SourceScrapeTestsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @source = create_source!(scraping_enabled: false)
    end

    test "POST create with source that has items performs scrape and returns HTML" do
      item = create_item_with_content!(@source, feed_word_count: 50)

      mock_scrape_result(item) do
        post source_monitor.source_scrape_test_path(@source)
      end

      assert_response :success
      assert_includes response.body, "Scrape Test Result"
      assert_includes response.body, item.title.truncate(60)
    end

    test "POST create with source that has no items redirects with alert" do
      post source_monitor.source_scrape_test_path(@source)

      assert_redirected_to source_monitor.source_path(@source)
      assert_equal "No items available for test scrape.", flash[:alert]
    end

    test "POST create turbo_stream format with items returns turbo stream modal" do
      item = create_item_with_content!(@source, feed_word_count: 100)

      mock_scrape_result(item) do
        post source_monitor.source_scrape_test_path(@source), as: :turbo_stream
      end

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_includes response.body, "scrape_test_modal_#{@source.id}"
      assert_includes response.body, "Scrape Test Result"
      assert_includes response.body, "Cancel"
      assert_includes response.body, "Enable Auto-Scraping"
    end

    test "POST create turbo_stream format with no items returns warning toast" do
      post source_monitor.source_scrape_test_path(@source), as: :turbo_stream

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_includes response.body, "No items with feed content available for test scrape."
    end

    test "POST create computes improvement percentage" do
      item = create_item_with_content!(@source, feed_word_count: 100)

      result = SourceMonitor::Scraping::ItemScraper::Result.new(
        status: :success, item: item, log: nil, message: "Scraped", error: nil
      )

      SourceMonitor::Scraping::ItemScraper.stub(:new, ->(**) {
        # Simulate scraping adding scraped content
        item.item_content.update_columns(scraped_word_count: 200)
        mock = Minitest::Mock.new
        mock.expect(:call, result)
        mock
      }) do
        post source_monitor.source_scrape_test_path(@source)
      end

      assert_response :success
      assert_includes response.body, "+100.0%"
    end

    test "source show page displays Test Scrape button when scraping is disabled" do
      get source_monitor.source_path(@source)

      assert_response :success
      assert_includes response.body, "Test Scrape"
      assert_includes response.body, source_monitor.source_scrape_test_path(@source)
    end

    test "source show page does not display Test Scrape button when scraping is enabled" do
      source = create_source!(scraping_enabled: true)

      get source_monitor.source_path(source)

      assert_response :success
      refute_includes response.body, "Test Scrape"
    end

    test "route helper source_scrape_test_path resolves correctly" do
      path = source_monitor.source_scrape_test_path(@source)
      assert_equal "/source_monitor/sources/#{@source.id}/scrape_test", path
    end

    private

    def create_item_with_content!(source, feed_word_count: 50)
      item = SourceMonitor::Item.new(
        source: source,
        title: "Test Article for Scrape",
        guid: "test-guid-#{SecureRandom.hex(4)}",
        url: "https://example.com/article-#{SecureRandom.hex(4)}",
        content: "word " * feed_word_count,
        published_at: 1.hour.ago
      )
      item.save!(validate: false)

      item_content = SourceMonitor::ItemContent.new(item: item)
      item_content.feed_word_count = feed_word_count
      item_content.save!

      item.reload
      item
    end

    def mock_scrape_result(item)
      result = SourceMonitor::Scraping::ItemScraper::Result.new(
        status: :success, item: item, log: nil, message: "Scraped successfully", error: nil
      )

      scraper_mock = Minitest::Mock.new
      scraper_mock.expect(:call, result)

      SourceMonitor::Scraping::ItemScraper.stub(:new, ->(**) { scraper_mock }) do
        yield
      end

      scraper_mock.verify
    end
  end
end
