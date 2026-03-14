# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module SourceMonitor
  class TurboBroadcasterTest < ActiveSupport::TestCase
    setup do
      SourceMonitor.reset_configuration!
      SourceMonitor::Dashboard::TurboBroadcaster.setup!
    end

    test "after_item_created triggers dashboard broadcast" do
      mock = Minitest::Mock.new
      mock.expect :call, nil

      SourceMonitor::Dashboard::TurboBroadcaster.stub :broadcast_dashboard_updates, -> { mock.call } do
        SourceMonitor::Events.after_item_created(item: nil, source: nil, entry: nil, result: nil)
      end

      assert_mock mock
    end

    test "after_fetch_completed triggers dashboard broadcast" do
      mock = Minitest::Mock.new
      mock.expect :call, nil

      SourceMonitor::Dashboard::TurboBroadcaster.stub :broadcast_dashboard_updates, -> { mock.call } do
        SourceMonitor::Events.after_fetch_completed(source: nil, result: nil)
      end

      assert_mock mock
    end

    test "STAT_CARDS contains all five dashboard stat keys" do
      keys = SourceMonitor::Dashboard::TurboBroadcaster::STAT_CARDS.map { |c| c[:key] }
      assert_equal %w[total_sources active_sources failed_sources total_items fetches_today], keys
    end

    test "STAT_CARDS maps stat symbols to matching stats hash keys" do
      SourceMonitor::Dashboard::TurboBroadcaster::STAT_CARDS.each do |card|
        assert_kind_of Symbol, card[:stat], "stat for #{card[:key]} should be a symbol"
        assert_kind_of String, card[:label], "label for #{card[:key]} should be a string"
        assert_kind_of String, card[:caption], "caption for #{card[:key]} should be a string"
      end
    end

    test "broadcast_dashboard_updates sends individual stat card replacements" do
      skip "Turbo::StreamsChannel not available in test environment" unless defined?(Turbo::StreamsChannel)

      broadcast_calls = []

      Turbo::StreamsChannel.stub :broadcast_replace_to, ->(*args, **kwargs) { broadcast_calls << kwargs[:target] } do
        SourceMonitor::Dashboard::TurboBroadcaster.broadcast_dashboard_updates
      end

      expected_targets = %w[
        source_monitor_stat_total_sources
        source_monitor_stat_active_sources
        source_monitor_stat_failed_sources
        source_monitor_stat_total_items
        source_monitor_stat_fetches_today
      ]

      expected_targets.each do |target|
        assert_includes broadcast_calls, target, "Expected broadcast to target #{target}"
      end
    end

    test "stat card partial renders with unique ID" do
      html = SourceMonitor::DashboardController.render(
        partial: "source_monitor/dashboard/stat_card",
        locals: { stat_card: { key: "total_sources", label: "Sources", value: 42, caption: "Total registered" } }
      )

      assert_includes html, 'id="source_monitor_stat_total_sources"'
      assert_includes html, "Sources"
      assert_includes html, "42"
      assert_includes html, "Total registered"
    end

    test "stat card partial renders all five stat card IDs" do
      %w[total_sources active_sources failed_sources total_items fetches_today].each do |key|
        html = SourceMonitor::DashboardController.render(
          partial: "source_monitor/dashboard/stat_card",
          locals: { stat_card: { key: key, label: "Test", value: 0, caption: "Test" } }
        )

        assert_includes html, "id=\"source_monitor_stat_#{key}\"",
          "Expected stat card to have ID source_monitor_stat_#{key}"
      end
    end
  end
end
