# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Health
    class SourceHealthResetTest < ActiveSupport::TestCase
      setup do
        clean_source_monitor_tables!
      end

      test "clears auto pause and failure state while scheduling next fetch" do
        travel_to Time.zone.parse("2025-10-22 10:00:00") do
          source = create_source!(
            health_status: "auto_paused",
            auto_paused_at: 4.hours.ago,
            auto_paused_until: 2.hours.from_now,
            rolling_success_rate: 0.1,
            failure_count: 6,
            last_error: "Feed unreachable",
            last_error_at: 3.hours.ago,
            backoff_until: 1.hour.from_now,
            next_fetch_at: 1.hour.from_now
          )

          SourceMonitor::Health::SourceHealthReset.call(source: source)

          source.reload

          assert_nil source.auto_paused_until
          assert_nil source.auto_paused_at
          assert_nil source.rolling_success_rate
          assert_equal 0, source.failure_count
          assert_nil source.last_error
          assert_nil source.last_error_at
          assert_nil source.backoff_until
          assert_equal "healthy", source.health_status
          assert_equal "idle", source.fetch_status

          expected_next_fetch_at = Time.current + source.fetch_interval_minutes.minutes
          assert_in_delta expected_next_fetch_at, source.next_fetch_at, 0.5
        end
      end

      test "uses configuration default when source interval missing" do
        travel_to Time.zone.parse("2025-10-22 12:00:00") do
          source = create_source!
          source.define_singleton_method(:fetch_interval_minutes) { nil }
          source.update!(
            health_status: "auto_paused",
            auto_paused_until: 30.minutes.from_now,
            rolling_success_rate: 0.2
          )

          SourceMonitor.config.fetching.min_interval_minutes = 15

          SourceMonitor::Health::SourceHealthReset.call(source: source)

          source.reload

          assert_in_delta Time.current + 15.minutes, source.next_fetch_at, 0.5
          assert_equal "healthy", source.health_status
        end
      end
    end
  end
end
