# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class SourceTest < ActiveSupport::TestCase
    test "is valid with minimal attributes" do
      source = Source.new(name: "Example", feed_url: "HTTPS://Example.com/Feed")

      assert source.valid?
    end

    test "normalizes feed and website URLs" do
      source = Source.create!(
        name: "Example",
        feed_url: "HTTPS://Example.COM",
        website_url: "http://Example.com"
      )

      assert_equal "https://example.com/", source.feed_url
      assert_equal "http://example.com/", source.website_url
    end

    test "rejects invalid feed URLs" do
      source = Source.new(name: "Bad", feed_url: "ftp://example.com/feed.xml")

      assert_not source.valid?
      assert_includes source.errors[:feed_url], "must be a valid HTTP(S) URL"
    end

    test "rejects malformed website URL" do
      source = Source.new(name: "Example", feed_url: "https://example.com/feed", website_url: "mailto:info@example.com")

      assert_not source.valid?
      assert_includes source.errors[:website_url], "must be a valid HTTP(S) URL"
    end

    test "enforces unique feed URLs" do
      Source.create!(name: "Example", feed_url: "https://example.com/feed")

      duplicate = Source.new(name: "Example 2", feed_url: "https://example.com/feed")

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:feed_url], "has already been taken"
    end

    test "rejects negative retention days" do
      source = Source.new(name: "Retention", feed_url: "https://example.com/feed.xml", items_retention_days: -1)

      assert_not source.valid?
      assert_includes source.errors[:items_retention_days], "must be greater than or equal to 0"
    end

    test "rejects negative max items" do
      source = Source.new(name: "Retention", feed_url: "https://example.com/feed.xml", max_items: -5)

      assert_not source.valid?
      assert_includes source.errors[:max_items], "must be greater than or equal to 0"
    end

    test "scopes reflect expected states" do
      healthy = Source.create!(name: "Healthy", feed_url: "https://example.com/healthy", next_fetch_at: 1.minute.ago)
      due_future = Source.create!(name: "Future", feed_url: "https://example.com/future", next_fetch_at: 10.minutes.from_now)
      inactive = Source.create!(name: "Inactive", feed_url: "https://example.com/inactive", active: false, next_fetch_at: 1.minute.ago)
      failed = Source.create!(
        name: "Failed",
        feed_url: "https://example.com/failed",
        failure_count: 2,
        last_error: "Timeout",
        last_error_at: 2.minutes.ago
      )

      assert_includes Source.active, healthy
      assert_not_includes Source.active, inactive

      assert_includes Source.due_for_fetch, healthy
      assert_not_includes Source.due_for_fetch, due_future

      assert_includes Source.failed, failed
      assert_not_includes Source.failed, healthy

      assert_includes Source.healthy, healthy
      assert_not_includes Source.healthy, failed
    end

    test "rejects health auto pause threshold outside 0 and 1" do
      source = Source.new(name: "Threshold", feed_url: "https://example.com/feed.xml", health_auto_pause_threshold: 1.5)

      assert_not source.valid?
      assert_includes source.errors[:health_auto_pause_threshold], "must be between 0 and 1"

      source.health_auto_pause_threshold = -0.1
      source.validate

      assert_includes source.errors[:health_auto_pause_threshold], "must be between 0 and 1"
    end

    test "auto_paused? reflects pause window" do
      source = Source.new(auto_paused_until: 5.minutes.from_now)

      assert source.auto_paused?

      source.auto_paused_until = 1.minute.ago

      assert_not source.auto_paused?
    end

    test "initializes with default hash attributes" do
      source = Source.new(name: "Test", feed_url: "https://example.com/feed")

      assert_equal({}, source.scrape_settings)
      assert_equal({}, source.custom_headers)
      assert_equal({}, source.metadata)
    end

    test "initializes with default fetch_status" do
      source = Source.new(name: "Test", feed_url: "https://example.com/feed")

      assert_equal "idle", source.fetch_status
    end

    test "initializes with default health_status" do
      source = Source.new(name: "Test", feed_url: "https://example.com/feed")

      assert_equal "healthy", source.health_status
    end

    test "allows overriding default hash attributes" do
      custom_settings = { "key" => "value" }
      source = Source.new(
        name: "Test",
        feed_url: "https://example.com/feed",
        scrape_settings: custom_settings
      )

      assert_equal custom_settings, source.scrape_settings
    end

    test "allows overriding default fetch_status" do
      source = Source.new(
        name: "Test",
        feed_url: "https://example.com/feed",
        fetch_status: "queued"
      )

      assert_equal "queued", source.fetch_status
    end

    test "allows overriding default health_status" do
      source = Source.new(
        name: "Test",
        feed_url: "https://example.com/feed",
        health_status: "degraded"
      )

      assert_equal "degraded", source.health_status
    end

    test "due_for_fetch uses current time by default" do
      past = Source.create!(name: "Past", feed_url: "https://example.com/past", next_fetch_at: 1.minute.ago)
      future = Source.create!(name: "Future", feed_url: "https://example.com/future", next_fetch_at: 10.minutes.from_now)

      assert_includes Source.due_for_fetch, past
      assert_not_includes Source.due_for_fetch, future
    end

    test "due_for_fetch accepts custom reference_time" do
      source = Source.create!(name: "Source", feed_url: "https://example.com/feed", next_fetch_at: 5.minutes.from_now)

      # Not due yet with current time
      assert_not_includes Source.due_for_fetch, source

      # Due when using future reference time
      assert_includes Source.due_for_fetch(reference_time: 10.minutes.from_now), source
    end

    test "due_for_fetch includes sources with nil next_fetch_at" do
      source = Source.create!(name: "No Schedule", feed_url: "https://example.com/feed", next_fetch_at: nil)

      assert_includes Source.due_for_fetch, source
    end

    test "reset_items_counter! recalculates counter cache from database" do
      source = Source.create!(name: "Counter Test", feed_url: "https://example.com/counter")

      # Create some items
      3.times do |i|
        Item.create!(source: source, guid: "item-#{i}", url: "https://example.com/item-#{i}")
      end

      source.reload
      assert_equal 3, source.items_count

      # Manually corrupt the counter
      source.update_columns(items_count: 99)
      assert_equal 99, source.reload.items_count

      # Reset should fix it
      source.reset_items_counter!
      assert_equal 3, source.reload.items_count
    end

    test "reset_items_counter! only counts active items" do
      source = Source.create!(name: "Soft Delete Counter", feed_url: "https://example.com/soft-delete")

      # Create 5 items
      items = 5.times.map do |i|
        Item.create!(source: source, guid: "item-#{i}", url: "https://example.com/item-#{i}")
      end

      source.reload
      assert_equal 5, source.items_count

      # Soft delete 2 items
      items[0].soft_delete!
      items[1].soft_delete!

      source.reload
      assert_equal 3, source.items_count

      # Corrupt counter
      source.update_columns(items_count: 10)

      # Reset should count only active items (3)
      source.reset_items_counter!
      assert_equal 3, source.reload.items_count
    end

    test "database rejects invalid fetch_status values" do
      source = Source.create!(name: "Status Test", feed_url: "https://example.com/status")

      # Valid statuses work
      %w[idle queued fetching failed invalid].each do |status|
        assert_nothing_raised do
          source.update_columns(fetch_status: status)
        end
      end

      # Invalid status is rejected at database level
      error = assert_raises(ActiveRecord::StatementInvalid) do
        source.update_columns(fetch_status: "bogus")
      end

      assert_match(/check_fetch_status_values/i, error.message)
    end

    test "avg_word_count returns average of scraped word counts" do
      source = create_source!
      item1 = SourceMonitor::Item.create!(
        source: source, guid: SecureRandom.uuid,
        url: "https://example.com/a-#{SecureRandom.hex(4)}", title: "A"
      )
      item2 = SourceMonitor::Item.create!(
        source: source, guid: SecureRandom.uuid,
        url: "https://example.com/b-#{SecureRandom.hex(4)}", title: "B"
      )
      SourceMonitor::ItemContent.create!(item: item1, scraped_content: "one two three four") # 4 words
      SourceMonitor::ItemContent.create!(item: item2, scraped_content: "one two three four five six") # 6 words

      assert_equal 5, source.avg_word_count # (4 + 6) / 2 = 5
    end

    test "avg_word_count returns nil when no item_contents have word counts" do
      source = create_source!
      assert_nil source.avg_word_count
    end
  end
end
