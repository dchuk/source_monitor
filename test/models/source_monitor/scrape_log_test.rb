# frozen_string_literal: true

require "test_helper"
require_relative "../../support/shared_loggable_tests"

module SourceMonitor
  class ScrapeLogTest < ActiveSupport::TestCase
    include SharedLoggableTests

    setup do
      @source = create_source!(name: "Example")
      @item = Item.create!(source: @source, guid: "abc-#{SecureRandom.hex(4)}", url: "https://example.com/article")
    end

    def build_loggable(overrides = {})
      ScrapeLog.new({ source: @source, item: @item, started_at: Time.current }.merge(overrides))
    end

    test "records scrape attempt" do
      log = ScrapeLog.new(
        source: @source,
        item: @item,
        success: true,
        started_at: Time.current,
        completed_at: 30.seconds.from_now,
        duration_ms: 30000,
        http_status: 200,
        scraper_adapter: "readability",
        content_length: 12_345,
        metadata: { extractor: "readability" }
      )

      assert log.save
      assert log.success
      assert_equal 12_345, log.content_length
    end

    test "validates source and item relationship" do
      other_source = create_source!(name: "Other", feed_url: "https://example.com/other")

      log = ScrapeLog.new(source: other_source, item: @item, started_at: Time.current)

      assert_not log.valid?
      assert_includes log.errors[:source], "must match item source"
    end

    test "enforces non-negative numeric fields" do
      log = ScrapeLog.new(source: @source, item: @item, started_at: Time.current, duration_ms: -1)

      assert_not log.valid?
      assert_includes log.errors[:duration_ms], "must be greater than or equal to 0"
    end

    test "by_source returns only logs for given source" do
      other_source = create_source!(name: "Other", feed_url: "https://example.com/other")
      other_item = Item.create!(source: other_source, guid: "other", url: "https://example.com/other-article")

      log1 = ScrapeLog.create!(source: @source, item: @item, started_at: Time.current, success: true)
      log2 = ScrapeLog.create!(source: other_source, item: other_item, started_at: Time.current, success: true)

      results = ScrapeLog.by_source(@source)
      assert_includes results, log1
      assert_not_includes results, log2
    end

    test "by_status filters by success value" do
      log_success = ScrapeLog.create!(source: @source, item: @item, started_at: Time.current, success: true)
      log_failure = ScrapeLog.create!(source: @source, item: @item, started_at: 1.minute.ago, success: false)

      assert_includes ScrapeLog.by_status(true), log_success
      assert_not_includes ScrapeLog.by_status(true), log_failure
      assert_includes ScrapeLog.by_status(false), log_failure
      assert_not_includes ScrapeLog.by_status(false), log_success
    end

    test "by_item returns logs for given item" do
      item2 = Item.create!(source: @source, guid: "def", url: "https://example.com/article2")
      log1 = ScrapeLog.create!(source: @source, item: @item, started_at: Time.current, success: true)
      log2 = ScrapeLog.create!(source: @source, item: item2, started_at: Time.current, success: true)

      results = ScrapeLog.by_item(@item)
      assert_includes results, log1
      assert_not_includes results, log2
    end

    test "scopes provide recent ordering" do
      latest = ScrapeLog.create!(source: @source, item: @item, started_at: 1.minute.ago, success: true)
      middle = ScrapeLog.create!(source: @source, item: @item, started_at: 5.minutes.ago, success: false)
      oldest = ScrapeLog.create!(source: @source, item: @item, started_at: 10.minutes.ago)

      assert_equal [ latest, middle, oldest ], ScrapeLog.where(source: @source).recent.to_a
      assert_equal [ latest ], ScrapeLog.where(source: @source).successful.to_a
      assert_equal [ middle ], ScrapeLog.where(source: @source).failed.to_a
    end
  end
end
