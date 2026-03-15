# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ImportHistoryTest < ActiveSupport::TestCase
    test "initializes JSONB attributes with defaults" do
      history = ImportHistory.new(user_id: 1)

      assert_equal [], history.imported_sources
      assert_equal [], history.failed_sources
      assert_equal [], history.skipped_duplicates
      assert_equal({}, history.bulk_settings)
    end

    test "imported_count returns size of imported_sources" do
      history = ImportHistory.new(imported_sources: [{ "id" => 1 }, { "id" => 2 }])
      assert_equal 2, history.imported_count
    end

    test "failed_count returns size of failed_sources" do
      history = ImportHistory.new(failed_sources: [{ "id" => 1 }])
      assert_equal 1, history.failed_count
    end

    test "skipped_count returns size of skipped_duplicates" do
      history = ImportHistory.new(skipped_duplicates: [{ "id" => 1 }, { "id" => 2 }, { "id" => 3 }])
      assert_equal 3, history.skipped_count
    end

    test "completed? returns true when completed_at is present" do
      history = ImportHistory.new(completed_at: Time.current)
      assert history.completed?
    end

    test "completed? returns false when completed_at is nil" do
      history = ImportHistory.new(completed_at: nil)
      assert_not history.completed?
    end

    test "duration_ms returns milliseconds between started_at and completed_at" do
      started = Time.zone.parse("2026-01-01 10:00:00")
      completed = Time.zone.parse("2026-01-01 10:00:05")
      history = ImportHistory.new(started_at: started, completed_at: completed)

      assert_equal 5000, history.duration_ms
    end

    test "duration_ms returns nil when started_at or completed_at is missing" do
      assert_nil ImportHistory.new(started_at: Time.current).duration_ms
      assert_nil ImportHistory.new(completed_at: Time.current).duration_ms
    end

    test "rejects completed_at before started_at" do
      history = ImportHistory.new(
        user_id: 1,
        started_at: Time.current,
        completed_at: 1.hour.ago
      )

      assert_not history.valid?
      assert_includes history.errors[:completed_at], "must be after started_at"
    end

    test "accepts completed_at after started_at" do
      history = ImportHistory.new(
        user_id: 1,
        started_at: 1.hour.ago,
        completed_at: Time.current
      )

      assert history.valid?
    end

    test "allows nil completed_at" do
      history = ImportHistory.new(user_id: 1)
      assert history.valid?
    end
  end
end
