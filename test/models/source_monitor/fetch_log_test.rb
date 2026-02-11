# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class FetchLogTest < ActiveSupport::TestCase
    setup do
      @source = Source.create!(name: "Example", feed_url: "https://example.com/feed")
    end

    test "creates log with metrics" do
      log = FetchLog.new(
        source: @source,
        success: true,
        items_created: 5,
        items_updated: 2,
        items_failed: 1,
        started_at: Time.current,
        completed_at: 1.minute.from_now,
        duration_ms: 60000,
        http_status: 200,
        http_response_headers: { "Content-Type" => "application/rss+xml" },
        metadata: { attempt: 1 }
      )

      assert log.save
      assert log.success
      assert_equal 5, log.items_created
    end

    test "validates non-negative counts" do
      log = FetchLog.new(source: @source, started_at: Time.current, items_created: -1)

      assert_not log.valid?
      assert_includes log.errors[:items_created], "must be greater than or equal to 0"
    end

    test "scopes filter by outcome and recency" do
      successful = FetchLog.create!(source: @source, success: true, started_at: 5.minutes.ago)
      failed = FetchLog.create!(source: @source, success: false, started_at: 2.minutes.ago)
      older = FetchLog.create!(source: @source, success: true, started_at: 10.minutes.ago)

      source_logs = FetchLog.where(source: @source)
      assert_equal [ failed, successful, older ], source_logs.recent.to_a
      assert_equal [ successful, older ], source_logs.successful.to_a
      assert_equal [ failed ], source_logs.failed.to_a
    end

    test "scopes by job id" do
      tracked = FetchLog.create!(source: @source, job_id: "abc-123", started_at: Time.current)
      FetchLog.create!(source: @source, job_id: "other", started_at: Time.current)

      assert_equal [ tracked ], FetchLog.for_job("abc-123").to_a
    end
  end
end
