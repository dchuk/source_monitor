# frozen_string_literal: true

require "test_helper"
require "securerandom"

module SourceMonitor
  class LogCleanupJobTest < ActiveJob::TestCase
    test "removes fetch and scrape logs older than the configured thresholds" do
      source = create_source!
      item = create_item!(source:)

      travel_to Time.zone.local(2025, 7, 1, 8, 0, 0) do
        create_labeled_fetch_log(source:, label: "old")
        create_labeled_scrape_log(source:, item:, label: "old")
      end

      travel_to Time.zone.local(2025, 9, 15, 10, 0, 0) do
        create_labeled_fetch_log(source:, label: "recent")
        create_labeled_scrape_log(source:, item:, label: "recent")

        SourceMonitor::LogCleanupJob.perform_now(
          now: Time.current,
          fetch_logs_older_than_days: 60,
          scrape_logs_older_than_days: 60
        )

        assert_equal [ "recent" ], SourceMonitor::FetchLog.where(source:).order(:created_at).pluck(Arel.sql("metadata->>'label'"))
        assert_equal [ "recent" ], SourceMonitor::ScrapeLog.where(source:).order(:created_at).pluck(Arel.sql("metadata->>'label'"))
      end
    end

    test "skips cleanup when negative thresholds provided" do
      source = create_source!
      item = create_item!(source:)

      travel_to Time.zone.local(2025, 6, 1, 12, 0, 0) do
        create_labeled_fetch_log(source:, label: "old")
        create_labeled_scrape_log(source:, item:, label: "old")
      end

      travel_to Time.zone.local(2025, 10, 10, 12, 0, 0) do
        SourceMonitor::LogCleanupJob.perform_now(
          now: Time.current,
          fetch_logs_older_than_days: -1,
          scrape_logs_older_than_days: 0
        )

        assert_equal 1, SourceMonitor::FetchLog.where(source:).count
        assert_equal 1, SourceMonitor::ScrapeLog.where(source:).count
      end
    end

    test "deletes LogEntry records before deleting fetch logs to prevent orphans" do
      source = create_source!

      travel_to Time.zone.local(2025, 6, 1, 12, 0, 0) do
        fetch_log = create_fetch_log!(source: source, metadata: { "label" => "old" })
        # sync_log_entry callback creates LogEntry automatically
        assert SourceMonitor::LogEntry.exists?(loggable: fetch_log), "LogEntry should exist after FetchLog save"
      end

      travel_to Time.zone.local(2025, 10, 10, 12, 0, 0) do
        SourceMonitor::LogCleanupJob.perform_now(
          now: Time.current,
          fetch_logs_older_than_days: 60,
          scrape_logs_older_than_days: 60
        )

        assert_equal 0, SourceMonitor::FetchLog.where(source: source).count
        assert_equal 0, SourceMonitor::LogEntry.where(source: source, loggable_type: "SourceMonitor::FetchLog").count,
          "LogEntry records should be deleted before their FetchLog records"
      end
    end

    test "deletes LogEntry records before deleting scrape logs to prevent orphans" do
      source = create_source!
      item = create_item!(source: source)

      travel_to Time.zone.local(2025, 6, 1, 12, 0, 0) do
        scrape_log = create_scrape_log!(item: item, source: source, success: true, metadata: { "label" => "old" })
        assert SourceMonitor::LogEntry.exists?(loggable: scrape_log), "LogEntry should exist after ScrapeLog save"
      end

      travel_to Time.zone.local(2025, 10, 10, 12, 0, 0) do
        SourceMonitor::LogCleanupJob.perform_now(
          now: Time.current,
          fetch_logs_older_than_days: 60,
          scrape_logs_older_than_days: 60
        )

        assert_equal 0, SourceMonitor::ScrapeLog.where(source: source).count
        assert_equal 0, SourceMonitor::LogEntry.where(source: source, loggable_type: "SourceMonitor::ScrapeLog").count,
          "LogEntry records should be deleted before their ScrapeLog records"
      end
    end

    private

    def create_labeled_fetch_log(source:, label:)
      create_fetch_log!(source: source, metadata: { "label" => label })
    end

    def create_labeled_scrape_log(source:, item:, label:)
      create_scrape_log!(item: item, source: source, success: true, metadata: { "label" => label })
    end
  end
end
