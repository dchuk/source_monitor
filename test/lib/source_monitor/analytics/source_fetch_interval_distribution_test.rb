# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Analytics
    class SourceFetchIntervalDistributionTest < ActiveSupport::TestCase
      setup_once do
        clean_source_monitor_tables!
      end

      test "groups sources into defined buckets" do
        intervals = [ 3, 10, 45, 90, 180, 360, 600 ]

        intervals.each_with_index do |interval, index|
          create_source!(
            name: "Source #{index}",
            feed_url: "https://example.com/#{index}.rss",
            fetch_interval_minutes: interval
          )
        end

        buckets = SourceMonitor::Analytics::SourceFetchIntervalDistribution
          .new(scope: SourceMonitor::Source.all)
          .buckets

        counts = buckets.map(&:count)

        assert_equal [ 2, 1, 1, 1, 1, 1 ], counts
      end
    end
  end
end
