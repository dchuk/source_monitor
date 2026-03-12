# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Dashboard
    class StatsQueryTest < ActiveSupport::TestCase
      setup do
        clean_source_monitor_tables!
      end

      test "health_distribution counts active sources by health_status" do
        create_source!(name: "Working 1", active: true, health_status: "working")
        create_source!(name: "Working 2", active: true, health_status: "working")
        create_source!(name: "Declining 1", active: true, health_status: "declining")
        create_source!(name: "Improving 1", active: true, health_status: "improving")
        create_source!(name: "Failing 1", active: true, health_status: "failing")
        create_source!(name: "Failing 2", active: true, health_status: "failing")

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 2, stats[:health_distribution]["working"]
        assert_equal 1, stats[:health_distribution]["declining"]
        assert_equal 1, stats[:health_distribution]["improving"]
        assert_equal 2, stats[:health_distribution]["failing"]
      end

      test "health_distribution excludes inactive sources" do
        create_source!(name: "Active Working", active: true, health_status: "working")
        create_source!(name: "Inactive Failing", active: false, health_status: "failing")

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 1, stats[:health_distribution]["working"]
        assert_equal 0, stats[:health_distribution]["failing"]
      end

      test "health_distribution includes zero for missing statuses" do
        create_source!(name: "Only Working", active: true, health_status: "working")

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 1, stats[:health_distribution]["working"]
        assert_equal 0, stats[:health_distribution]["declining"]
        assert_equal 0, stats[:health_distribution]["improving"]
        assert_equal 0, stats[:health_distribution]["failing"]
      end

      test "health_distribution handles no active sources" do
        create_source!(name: "Inactive", active: false, health_status: "working")

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_equal 0, stats[:health_distribution]["working"]
        assert_equal 0, stats[:health_distribution]["declining"]
        assert_equal 0, stats[:health_distribution]["improving"]
        assert_equal 0, stats[:health_distribution]["failing"]
      end

      test "scrape_candidates_count is returned in stats hash" do
        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_includes stats.keys, :scrape_candidates_count
        assert_kind_of Integer, stats[:scrape_candidates_count]
      end

      test "scrape_candidates_count reflects actual candidate count" do
        SourceMonitor.configure do |config|
          config.scraping.scrape_recommendation_threshold = 200
        end

        source = create_source!(name: "Low WC Stats #{SecureRandom.hex(4)}", scraping_enabled: false)
        item = SourceMonitor::Item.create!(
          source: source,
          guid: SecureRandom.uuid,
          url: "https://example.com/stats-#{SecureRandom.hex(4)}",
          content: "short content"
        )
        SourceMonitor::ItemContent.create!(item: item)

        stats = SourceMonitor::Dashboard::Queries::StatsQuery.new(reference_time: Time.current).call

        assert_operator stats[:scrape_candidates_count], :>=, 1
      end
    end
  end
end
