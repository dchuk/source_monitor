# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class SourcesControllerSortTest < ActionDispatch::IntegrationTest
    setup do
      @source_high = create_source!(name: "High Words Source")
      @source_low = create_source!(name: "Low Words Source")
      @source_empty = create_source!(name: "Empty Source")

      # Create items with item_contents for @source_high (high word counts)
      item_high = SourceMonitor::Item.create!(
        source: @source_high,
        guid: "high-1",
        title: "High Article",
        url: "https://example.com/high/1",
        content: "word " * 200
      )
      item_high.ensure_feed_content_record
      item_high.item_content.update_columns(feed_word_count: 200, scraped_word_count: 500)

      item_high2 = SourceMonitor::Item.create!(
        source: @source_high,
        guid: "high-2",
        title: "High Article 2",
        url: "https://example.com/high/2",
        content: "word " * 100
      )
      item_high2.ensure_feed_content_record
      item_high2.item_content.update_columns(feed_word_count: 100, scraped_word_count: 300)

      # Create items with item_contents for @source_low (low word counts)
      item_low = SourceMonitor::Item.create!(
        source: @source_low,
        guid: "low-1",
        title: "Low Article",
        url: "https://example.com/low/1",
        content: "word " * 10
      )
      item_low.ensure_feed_content_record
      item_low.item_content.update_columns(feed_word_count: 10, scraped_word_count: 20)

      # @source_empty has no items -- tests NULL handling
    end

    test "sorts by avg_feed_words descending" do
      get "/source_monitor/sources", params: { q: { s: "avg_feed_words desc" } }

      assert_response :success
      body = response.body
      high_pos = body.index(@source_high.name)
      low_pos = body.index(@source_low.name)
      assert high_pos < low_pos, "High word source should appear before low word source in desc order"
    end

    test "sorts by avg_feed_words ascending" do
      get "/source_monitor/sources", params: { q: { s: "avg_feed_words asc" } }

      assert_response :success
      body = response.body
      high_pos = body.index(@source_high.name)
      low_pos = body.index(@source_low.name)
      assert low_pos < high_pos, "Low word source should appear before high word source in asc order"
    end

    test "sorts by avg_scraped_words descending" do
      get "/source_monitor/sources", params: { q: { s: "avg_scraped_words desc" } }

      assert_response :success
      body = response.body
      high_pos = body.index(@source_high.name)
      low_pos = body.index(@source_low.name)
      assert high_pos < low_pos, "High scraped source should appear before low scraped source in desc order"
    end

    test "sorts by avg_scraped_words ascending" do
      get "/source_monitor/sources", params: { q: { s: "avg_scraped_words asc" } }

      assert_response :success
      body = response.body
      high_pos = body.index(@source_high.name)
      low_pos = body.index(@source_low.name)
      assert low_pos < high_pos, "Low scraped source should appear before high scraped source in asc order"
    end

    test "sorts by new_items_per_day descending" do
      get "/source_monitor/sources", params: { q: { s: "new_items_per_day desc" } }

      assert_response :success
      body = response.body
      # @source_high has 2 items, @source_low has 1, @source_empty has 0
      high_pos = body.index(@source_high.name)
      low_pos = body.index(@source_low.name)
      assert high_pos < low_pos, "Source with more items should appear first in desc order"
    end

    test "sort arrows reflect current sort direction for avg_feed_words desc" do
      get "/source_monitor/sources", params: { q: { s: "avg_feed_words desc" } }

      assert_response :success
      assert_includes response.body, 'aria-sort="descending"'
    end

    test "NULL handling: sources with no items sort without errors" do
      get "/source_monitor/sources", params: { q: { s: "avg_feed_words desc" } }

      assert_response :success
      assert_includes response.body, @source_empty.name
    end

    test "NULL handling: sources with no items sort without errors for new_items_per_day" do
      get "/source_monitor/sources", params: { q: { s: "new_items_per_day desc" } }

      assert_response :success
      assert_includes response.body, @source_empty.name
    end

    test "NULL handling: sources with no items sort without errors for avg_scraped_words" do
      get "/source_monitor/sources", params: { q: { s: "avg_scraped_words asc" } }

      assert_response :success
      assert_includes response.body, @source_empty.name
    end
  end
end
