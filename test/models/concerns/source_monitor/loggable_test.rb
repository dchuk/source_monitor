# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class LoggableDateScopesTest < ActiveSupport::TestCase
    setup do
      @source = Source.create!(name: "Loggable Test", feed_url: "https://example.com/loggable")
    end

    test "since scope returns logs on or after date" do
      old_log = FetchLog.create!(source: @source, started_at: 3.days.ago)
      recent_log = FetchLog.create!(source: @source, started_at: 1.day.ago)

      results = FetchLog.where(source: @source).since(2.days.ago)

      assert_includes results, recent_log
      assert_not_includes results, old_log
    end

    test "before scope returns logs on or before date" do
      old_log = FetchLog.create!(source: @source, started_at: 3.days.ago)
      recent_log = FetchLog.create!(source: @source, started_at: 1.day.ago)

      results = FetchLog.where(source: @source).before(2.days.ago)

      assert_includes results, old_log
      assert_not_includes results, recent_log
    end

    test "today scope returns only today's logs" do
      yesterday_log = FetchLog.create!(source: @source, started_at: 1.day.ago)
      today_log = FetchLog.create!(source: @source, started_at: Time.current)

      results = FetchLog.where(source: @source).today

      assert_includes results, today_log
      assert_not_includes results, yesterday_log
    end

    test "by_date_range scope returns logs within range" do
      old_log = FetchLog.create!(source: @source, started_at: 5.days.ago)
      middle_log = FetchLog.create!(source: @source, started_at: 3.days.ago)
      recent_log = FetchLog.create!(source: @source, started_at: 1.day.ago)

      results = FetchLog.where(source: @source).by_date_range(4.days.ago, 2.days.ago)

      assert_includes results, middle_log
      assert_not_includes results, old_log
      assert_not_includes results, recent_log
    end

    test "date scopes are chainable with existing scopes" do
      FetchLog.create!(source: @source, success: true, started_at: Time.current)
      FetchLog.create!(source: @source, success: false, started_at: Time.current)
      FetchLog.create!(source: @source, success: true, started_at: 2.days.ago)

      results = FetchLog.where(source: @source).successful.today

      assert_equal 1, results.count
      assert results.first.success
    end

    test "composite indexes exist on log tables" do
      connection = ActiveRecord::Base.connection

      assert connection.index_exists?(:sourcemon_fetch_logs, [ :source_id, :started_at ])
      assert connection.index_exists?(:sourcemon_scrape_logs, [ :source_id, :started_at ])
      assert connection.index_exists?(:sourcemon_scrape_logs, [ :item_id, :started_at ])
      assert connection.index_exists?(:sourcemon_health_check_logs, [ :source_id, :started_at ])
    end
  end
end
