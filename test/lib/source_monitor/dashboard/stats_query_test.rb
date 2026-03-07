# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Dashboard
    class StatsQueryTest < ActiveSupport::TestCase
      setup do
        clean_source_monitor_tables!
      end

      test "health_distribution counts active sources by health_status" do
        create_source!(name: "Healthy 1", active: true, health_status: "healthy")
        create_source!(name: "Healthy 2", active: true, health_status: "healthy")
        create_source!(name: "Warning 1", active: true, health_status: "warning")
        create_source!(name: "Declining 1", active: true, health_status: "declining")
        create_source!(name: "Critical 1", active: true, health_status: "critical")
        create_source!(name: "Critical 2", active: true, health_status: "critical")

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 2, stats[:health_distribution]["healthy"]
        assert_equal 1, stats[:health_distribution]["warning"]
        assert_equal 1, stats[:health_distribution]["declining"]
        assert_equal 2, stats[:health_distribution]["critical"]
      end

      test "health_distribution excludes inactive sources" do
        create_source!(name: "Active Healthy", active: true, health_status: "healthy")
        create_source!(name: "Inactive Critical", active: false, health_status: "critical")

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 1, stats[:health_distribution]["healthy"]
        assert_equal 0, stats[:health_distribution]["critical"]
      end

      test "health_distribution includes zero for missing statuses" do
        create_source!(name: "Only Healthy", active: true, health_status: "healthy")

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 1, stats[:health_distribution]["healthy"]
        assert_equal 0, stats[:health_distribution]["warning"]
        assert_equal 0, stats[:health_distribution]["declining"]
        assert_equal 0, stats[:health_distribution]["critical"]
      end

      test "health_distribution handles no active sources" do
        create_source!(name: "Inactive", active: false, health_status: "healthy")

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 0, stats[:health_distribution]["healthy"]
        assert_equal 0, stats[:health_distribution]["warning"]
        assert_equal 0, stats[:health_distribution]["declining"]
        assert_equal 0, stats[:health_distribution]["critical"]
      end
    end
  end
end
