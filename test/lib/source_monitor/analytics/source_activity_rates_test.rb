# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Analytics
    class SourceActivityRatesTest < ActiveSupport::TestCase
      setup_once do
        clean_source_monitor_tables!
      end

      test "returns average items per day within the lookback window" do
        travel_to Time.zone.local(2025, 10, 10, 12, 0, 0) do
          source_a = create_source!(
            name: "Active Source",
            feed_url: "https://example.com/a.rss",
            fetch_interval_minutes: 60
          )

          source_b = create_source!(
            name: "Less Active",
            feed_url: "https://example.com/b.rss",
            fetch_interval_minutes: 120
          )

          3.times do |index|
            SourceMonitor::Item.create!(
              source: source_a,
              guid: "active-#{index}",
              title: "Active #{index}",
              url: "https://example.com/a/#{index}",
              created_at: 2.days.ago,
              published_at: 2.days.ago
            )
          end

          SourceMonitor::Item.create!(
            source: source_a,
            guid: "active-outside",
            title: "Outside window",
            url: "https://example.com/a/outside",
            created_at: 10.days.ago,
            published_at: 10.days.ago
          )

          SourceMonitor::Item.create!(
            source: source_b,
            guid: "less-1",
            title: "Less Active",
            url: "https://example.com/b/1",
            created_at: 1.day.ago,
            published_at: 1.day.ago
          )

          rates = SourceMonitor::Analytics::SourceActivityRates
            .new(scope: SourceMonitor::Source.all, lookback: 7.days, now: Time.current)
            .per_source_rates

          assert_in_delta(3.0 / 7, rates[source_a.id], 0.0001)
          assert_in_delta(1.0 / 7, rates[source_b.id], 0.0001)
        end
      end
    end
  end
end
