# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Dashboard
    class UpcomingFetchScheduleTest < ActiveSupport::TestCase
      setup do
        clean_source_monitor_tables!
      end

      test "groups sources into correct time buckets using AR scopes" do
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

          schedule = SourceMonitor::Dashboard::UpcomingFetchSchedule.new(scope: SourceMonitor::Source.all)
          groups = schedule.groups.index_by(&:key)

          assert_includes groups.fetch("0-30").sources, near_term
          assert_includes groups.fetch("60-120").sources, mid_term
          assert_includes groups.fetch("240+").sources, long_term

          assert_equal schedule.reference_time.to_date, Date.new(2025, 10, 11)
        end
      end

      test "hides empty buckets" do
        travel_to(Time.zone.parse("2025-10-11 12:00:00")) do
          create_source!(
            name: "Only Near",
            next_fetch_at: 10.minutes.from_now
          )

          schedule = SourceMonitor::Dashboard::UpcomingFetchSchedule.new(scope: SourceMonitor::Source.all)
          keys = schedule.groups.map(&:key)

          assert_includes keys, "0-30"
          refute_includes keys, "30-60"
          refute_includes keys, "60-120"
          refute_includes keys, "120-240"
          refute_includes keys, "240+"
        end
      end

      test "paginates within a bucket" do
        travel_to(Time.zone.parse("2025-10-11 12:00:00")) do
          15.times do |i|
            create_source!(
              name: "Source #{i.to_s.rjust(2, '0')}",
              next_fetch_at: (i + 1).minutes.from_now
            )
          end

          # Page 1 with per_page 10
          schedule = SourceMonitor::Dashboard::UpcomingFetchSchedule.new(
            scope: SourceMonitor::Source.all,
            per_page: 10
          )
          group = schedule.groups.find { |g| g.key == "0-30" }

          assert_equal 10, group.sources.size
          assert_equal 1, group.page
          assert group.has_next_page
          refute group.has_previous_page

          # Page 2
          schedule_p2 = SourceMonitor::Dashboard::UpcomingFetchSchedule.new(
            scope: SourceMonitor::Source.all,
            per_page: 10,
            pages: { "0-30" => 2 }
          )
          group_p2 = schedule_p2.groups.find { |g| g.key == "0-30" }

          assert_equal 5, group_p2.sources.size
          assert_equal 2, group_p2.page
          refute group_p2.has_next_page
          assert group_p2.has_previous_page
        end
      end

      test "includes unscheduled sources in the 240+ bucket" do
        travel_to(Time.zone.parse("2025-10-11 12:00:00")) do
          unscheduled = create_source!(
            name: "Pending",
            fetch_interval_minutes: 120,
            next_fetch_at: nil
          )

          schedule = SourceMonitor::Dashboard::UpcomingFetchSchedule.new(scope: SourceMonitor::Source.all)
          beyond_group = schedule.groups.find { |g| g.key == "240+" }

          assert_not_nil beyond_group
          assert_includes beyond_group.sources, unscheduled
        end
      end

      test "respects per-bucket page params" do
        travel_to(Time.zone.parse("2025-10-11 12:00:00")) do
          12.times do |i|
            create_source!(
              name: "Bucket Source #{i.to_s.rjust(2, '0')}",
              next_fetch_at: (i + 1).minutes.from_now
            )
          end

          schedule = SourceMonitor::Dashboard::UpcomingFetchSchedule.new(
            scope: SourceMonitor::Source.all,
            per_page: 10,
            pages: { "0-30" => 2 }
          )
          group = schedule.groups.find { |g| g.key == "0-30" }

          assert_equal 2, group.page
          assert_equal 2, group.sources.size
          refute group.has_next_page
          assert group.has_previous_page
        end
      end

      test "groups include pagination fields" do
        travel_to(Time.zone.parse("2025-10-11 12:00:00")) do
          create_source!(name: "Single", next_fetch_at: 5.minutes.from_now)

          schedule = SourceMonitor::Dashboard::UpcomingFetchSchedule.new(scope: SourceMonitor::Source.all)
          group = schedule.groups.first

          assert_equal 1, group.page
          refute group.has_next_page
          refute group.has_previous_page
        end
      end

      test "bucket boundary sources land in correct bucket" do
        travel_to(Time.zone.parse("2025-10-11 12:00:00")) do
          # Source at exactly 30 minutes should be in "30-60", not "0-30"
          boundary_source = create_source!(
            name: "Boundary",
            next_fetch_at: 30.minutes.from_now
          )

          schedule = SourceMonitor::Dashboard::UpcomingFetchSchedule.new(scope: SourceMonitor::Source.all)
          groups = schedule.groups.index_by(&:key)

          # Exclusive end on 0-30 range means exactly 30 goes to 30-60
          assert_includes groups.fetch("30-60").sources, boundary_source
          assert_nil groups["0-30"]
        end
      end
    end
  end
end
