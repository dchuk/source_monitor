# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Dashboard
    class UpcomingFetchScheduleTest < ActiveSupport::TestCase
      setup do
        clean_source_monitor_tables!
      end

      test "groups sources into defined windows" do
        travel_to(Time.zone.parse("2025-10-11 12:00:00")) do
          near_term = create_source!(
            name: "Immediate",
            fetch_interval_minutes: 15,
            next_fetch_at: 10.minutes.from_now
          )

          mid_term = create_source!(
            name: "In Ninety",
            fetch_interval_minutes: 90,
            next_fetch_at: 70.minutes.from_now
          )

          long_term = create_source!(
            name: "Later",
            fetch_interval_minutes: 360,
            next_fetch_at: 5.hours.from_now
          )

          unscheduled = create_source!(
            name: "Pending",
            fetch_interval_minutes: 120,
            next_fetch_at: nil
          )

          schedule = SourceMonitor::Dashboard::UpcomingFetchSchedule.new(scope: SourceMonitor::Source.all)
          groups = schedule.groups.index_by(&:key)

          assert_includes groups.fetch("0-30").sources, near_term
          assert_includes groups.fetch("60-120").sources, mid_term

          beyond_group = groups.fetch("240+")
          assert_includes beyond_group.sources, long_term
          assert_includes beyond_group.sources, unscheduled

          assert_equal schedule.reference_time.to_date, Date.new(2025, 10, 11)
        end
      end
    end
  end
end
