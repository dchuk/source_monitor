# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ItemScrapesControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper
    include ActionView::RecordIdentifier

    setup do
      @source = create_source!(scraping_enabled: true)
      @item = SourceMonitor::Item.create!(
        source: @source,
        guid: SecureRandom.uuid,
        url: "https://example.com/article-#{SecureRandom.hex(4)}",
        title: "Test Article"
      )
    end

    teardown do
      clear_enqueued_jobs
    end

    test "create enqueues scrape and renders turbo stream" do
      post source_monitor.item_scrape_path(@item), as: :turbo_stream

      assert_response :ok
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_includes response.body, "Scrape has been enqueued"
    end

    test "create with html format redirects to item path" do
      post source_monitor.item_scrape_path(@item)

      assert_redirected_to source_monitor.item_path(@item)
      assert_equal "Scrape has been enqueued and will run shortly.", flash[:notice]
    end

    test "create when enqueue fails returns unprocessable_entity" do
      @source.update_columns(scraping_enabled: false)

      post source_monitor.item_scrape_path(@item), as: :turbo_stream

      assert_response :unprocessable_entity
      assert_equal "text/vnd.turbo-stream.html", response.media_type
    end

    test "create when item already enqueued returns ok with notice" do
      @item.update_columns(scrape_status: "queued")

      post source_monitor.item_scrape_path(@item), as: :turbo_stream

      assert_response :ok
      assert_equal "text/vnd.turbo-stream.html", response.media_type
    end
  end
end
