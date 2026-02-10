# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Analytics
    class SourcesIndexMetricsTest < ActiveSupport::TestCase
      setup do
        clean_source_monitor_tables!

        travel_to Time.current.change(usec: 0)

        @fast_source = create_source!(name: "Fast", fetch_interval_minutes: 30)
        @medium_source = create_source!(name: "Medium", fetch_interval_minutes: 120)
        @slow_source = create_source!(name: "Slow", fetch_interval_minutes: 480)

        SourceMonitor::Item.create!(
          source: @fast_source,
          guid: SecureRandom.uuid,
          url: "https://example.com/fast-1",
          title: "Fast 1",
          created_at: 1.day.ago,
          published_at: 1.day.ago
        )

        SourceMonitor::Item.create!(
          source: @fast_source,
          guid: SecureRandom.uuid,
          url: "https://example.com/fast-2",
          title: "Fast 2",
          created_at: 2.days.ago,
          published_at: 2.days.ago
        )

        SourceMonitor::Item.create!(
          source: @medium_source,
          guid: SecureRandom.uuid,
          url: "https://example.com/medium-1",
          title: "Medium 1",
          created_at: 12.hours.ago,
          published_at: 12.hours.ago
        )
      end

      teardown do
        travel_back
      end

      test "computes fetch interval distribution and activity rates" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {},
          lookback: 2.days,
          now: Time.current
        )

        distribution = metrics.fetch_interval_distribution
        assert distribution.any? { |bucket| bucket.label == "30-60 min" && bucket.count == 1 }
        assert distribution.any? { |bucket| bucket.label == "120-240 min" && bucket.count == 1 }
        assert distribution.any? { |bucket| bucket.label == "480+ min" && bucket.count == 1 }

        activity_rates = metrics.item_activity_rates
        assert_in_delta 1.0, activity_rates[@fast_source.id], 0.01
        assert_in_delta 0.5, activity_rates[@medium_source.id], 0.01
        assert_in_delta 0.0, activity_rates[@slow_source.id], 0.01
      end

      test "selects fetch interval bucket based on sanitized filter" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {
            "fetch_interval_minutes_gteq" => "60",
            "fetch_interval_minutes_lt" => "120<script>"
          },
          lookback: 2.days,
          now: Time.current
        )

        bucket = metrics.selected_fetch_interval_bucket

        assert_equal 60, bucket.min
        assert_equal 120, bucket.max
      end

      test "excludes fetch interval filters when building distribution scope" do
        scope = SourceMonitor::Source.where(name: %w[Fast Medium Slow])
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {
            "name_cont" => "Fast",
            "fetch_interval_minutes_gteq" => "60",
            "fetch_interval_minutes_lteq" => "90"
          },
          lookback: 2.days,
          now: Time.current
        )

        distribution_scope_ids = metrics.send(:distribution_source_ids)

        assert_includes distribution_scope_ids, @fast_source.id
        refute_includes distribution_scope_ids, @medium_source.id
      end

      # === Task 4: SourcesIndexMetrics edge cases ===

      test "fetch_interval_filter returns nil when no interval params present" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: { "name_cont" => "Fast" }
        )

        assert_nil metrics.fetch_interval_filter
      end

      test "fetch_interval_filter returns min and max from gteq and lt params" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {
            "fetch_interval_minutes_gteq" => "60",
            "fetch_interval_minutes_lt" => "120"
          }
        )

        filter = metrics.fetch_interval_filter
        assert_equal 60, filter[:min]
        assert_equal 120, filter[:max]
      end

      test "fetch_interval_filter uses lteq when lt is absent" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {
            "fetch_interval_minutes_gteq" => "30",
            "fetch_interval_minutes_lteq" => "240"
          }
        )

        filter = metrics.fetch_interval_filter
        assert_equal 30, filter[:min]
        assert_equal 240, filter[:max]
      end

      test "fetch_interval_filter prefers lt over lteq" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {
            "fetch_interval_minutes_gteq" => "60",
            "fetch_interval_minutes_lt" => "120",
            "fetch_interval_minutes_lteq" => "240"
          }
        )

        filter = metrics.fetch_interval_filter
        assert_equal 120, filter[:max]
      end

      test "fetch_interval_filter returns only min when max params are absent" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: { "fetch_interval_minutes_gteq" => "480" }
        )

        filter = metrics.fetch_interval_filter
        assert_equal 480, filter[:min]
        assert_nil filter[:max]
      end

      test "integer_param returns nil for blank values" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {
            "fetch_interval_minutes_gteq" => "",
            "fetch_interval_minutes_lt" => nil
          }
        )

        assert_nil metrics.fetch_interval_filter
      end

      test "integer_param returns nil for non-numeric strings" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: { "fetch_interval_minutes_gteq" => "abc" }
        )

        assert_nil metrics.fetch_interval_filter
      end

      test "integer_param sanitizes HTML tags and returns nil for unparseable result" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: { "fetch_interval_minutes_gteq" => "60<script>alert(1)</script>" }
        )

        # After sanitization "60<script>alert(1)</script>" becomes "60alert(1)"
        # which fails Integer() parsing, so filter returns nil
        assert_nil metrics.fetch_interval_filter
      end

      test "selected_fetch_interval_bucket returns nil when no filter is set" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {}
        )

        assert_nil metrics.selected_fetch_interval_bucket
      end

      test "selected_fetch_interval_bucket matches bucket with nil max" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: { "fetch_interval_minutes_gteq" => "480" }
        )

        bucket = metrics.selected_fetch_interval_bucket
        assert_not_nil bucket
        assert_equal 480, bucket.min
        assert_nil bucket.max
      end

      test "selected_fetch_interval_bucket returns nil for non-matching filter" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {
            "fetch_interval_minutes_gteq" => "999",
            "fetch_interval_minutes_lt" => "1000"
          }
        )

        assert_nil metrics.selected_fetch_interval_bucket
      end

      test "distribution_scope uses base_scope when no non-interval params" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {
            "fetch_interval_minutes_gteq" => "60",
            "fetch_interval_minutes_lt" => "120"
          }
        )

        distribution_ids = metrics.send(:distribution_source_ids)
        assert_includes distribution_ids, @fast_source.id
        assert_includes distribution_ids, @medium_source.id
        assert_includes distribution_ids, @slow_source.id
      end

      test "distribution_scope applies ransack when non-interval search params present" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {
            "name_cont" => "Medium",
            "fetch_interval_minutes_gteq" => "60"
          }
        )

        distribution_ids = metrics.send(:distribution_source_ids)
        assert_includes distribution_ids, @medium_source.id
        refute_includes distribution_ids, @fast_source.id
        refute_includes distribution_ids, @slow_source.id
      end

      test "search_params are duplicated and do not mutate original" do
        original_params = { "name_cont" => "Fast", "fetch_interval_minutes_gteq" => "60" }
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: original_params
        )

        assert_equal original_params, metrics.search_params
        assert_not_same original_params, metrics.search_params
      end

      test "handles nil search_params gracefully" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: nil
        )

        assert_nil metrics.fetch_interval_filter
        assert_nil metrics.selected_fetch_interval_bucket
      end

      test "fetch_interval_distribution returns buckets from distribution scope" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {}
        )

        distribution = metrics.fetch_interval_distribution

        assert_kind_of Array, distribution
        assert distribution.all? { |b| b.respond_to?(:label) && b.respond_to?(:count) }
      end

      test "item_activity_rates delegates to SourceActivityRates" do
        scope = SourceMonitor::Source.all
        metrics = SourceMonitor::Analytics::SourcesIndexMetrics.new(
          base_scope: scope,
          result_scope: scope,
          search_params: {},
          lookback: 2.days,
          now: Time.current
        )

        rates = metrics.item_activity_rates
        assert_kind_of Hash, rates
        assert rates.key?(@fast_source.id)
        assert rates.key?(@slow_source.id)
      end
    end
  end
end
