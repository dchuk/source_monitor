# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ItemsControllerTest < ActionDispatch::IntegrationTest
    test "sanitizes search params before rendering" do
      get "/source_monitor/items", params: {
        q: {
          "title_or_summary_or_url_or_source_name_cont" => "<img src=x onerror=alert(3)>"
        }
      }

      assert_response :success
      response_body = response.body
      refute_includes response_body, "%3Cimg"
      refute_includes response_body, "&lt;img"
    end

    test "paginates items and ignores invalid page numbers" do
      source = create_source!
      items = Array.new(2) do |index|
        SourceMonitor::Item.create!(
          source: source,
          guid: SecureRandom.uuid,
          url: "https://example.com/articles/#{index}",
          title: "Item #{index}"
        )
      end

      get "/source_monitor/items", params: { page: "-5" }

      assert_response :success
      assert_includes response.body, items.last.title
    end

    test "index renders published_at date when present" do
      source = create_source!
      published_time = Time.utc(2025, 10, 6, 12, 0, 0)
      SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/dated-item",
        title: "Dated Item",
        published_at: published_time
      )

      get "/source_monitor/items"

      assert_response :success
      assert_includes response.body, "Oct 06, 2025 12:00"
      refute_includes response.body, "Unpublished"
    end

    test "index shows created_at fallback when published_at is nil" do
      source = create_source!
      item = SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/undated-item",
        title: "Undated Item"
      )

      get "/source_monitor/items"

      assert_response :success
      refute_includes response.body, "Unpublished"
      assert_includes response.body, item.created_at.strftime("%b %d, %Y %H:%M")
    end

    test "show renders published_at date when present" do
      source = create_source!
      published_time = Time.utc(2025, 10, 6, 12, 0, 0)
      item = SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/dated-item-show",
        title: "Dated Item Show",
        published_at: published_time
      )

      get "/source_monitor/items/#{item.id}"

      assert_response :success
      assert_includes response.body, "Oct 06, 2025 12:00"
    end

    test "show renders created_at fallback when published_at is nil" do
      source = create_source!
      item = SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/undated-item-show",
        title: "Undated Item Show"
      )

      get "/source_monitor/items/#{item.id}"

      assert_response :success
      refute_includes response.body, "Unpublished"
      assert_includes response.body, item.created_at.strftime("%b %d, %Y %H:%M")
    end

    test "index renders Words column header" do
      get "/source_monitor/items"
      assert_response :success
      assert_includes response.body, "Words"
    end

    test "index renders word count for items with scraped content" do
      source = create_source!
      item = SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/word-count-item",
        title: "Word Count Item"
      )
      SourceMonitor::ItemContent.create!(item: item, scraped_content: "one two three")

      get "/source_monitor/items"

      assert_response :success
      assert_includes response.body, "3"
    end

    test "show renders word counts in Counts & Metrics section" do
      source = create_source!
      item = SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/word-count-detail",
        title: "Word Count Detail",
        content: "<p>Hello world test</p>"
      )
      SourceMonitor::ItemContent.create!(item: item, scraped_content: "one two three four five")

      get "/source_monitor/items/#{item.id}"

      assert_response :success
      assert_includes response.body, "Feed Word Count"
      assert_includes response.body, "Scraped Word Count"
      assert_includes response.body, "5"
    end
  end
end
