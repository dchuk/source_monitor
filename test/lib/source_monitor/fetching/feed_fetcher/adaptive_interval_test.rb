# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcher
      class AdaptiveIntervalTest < ActiveSupport::TestCase
        setup do
          @source = create_source!(
            name: "Adaptive Test",
            fetch_interval_minutes: 60,
            adaptive_fetching_enabled: true
          )
          @no_jitter = ->(_) { 0 }
          @adaptive = AdaptiveInterval.new(source: @source, jitter_proc: @no_jitter)
        end

        # --- compute_next_interval_seconds ---

        test "decreases interval when content changed" do
          result = @adaptive.compute_next_interval_seconds(content_changed: true, failure: false)

          expected = 60 * 60.0 * AdaptiveInterval::DECREASE_FACTOR
          assert_in_delta expected, result, 0.01
        end

        test "increases interval when content unchanged" do
          result = @adaptive.compute_next_interval_seconds(content_changed: false, failure: false)

          expected = 60 * 60.0 * AdaptiveInterval::INCREASE_FACTOR
          assert_in_delta expected, result, 0.01
        end

        test "increases interval with failure factor on failure" do
          result = @adaptive.compute_next_interval_seconds(content_changed: false, failure: true)

          expected = 60 * 60.0 * AdaptiveInterval::FAILURE_INCREASE_FACTOR
          assert_in_delta expected, result, 0.01
        end

        test "clamps to minimum interval" do
          @source.update_columns(fetch_interval_minutes: 1)
          adaptive = AdaptiveInterval.new(source: @source, jitter_proc: @no_jitter)

          result = adaptive.compute_next_interval_seconds(content_changed: true, failure: false)

          assert_operator result, :>=, AdaptiveInterval::MIN_FETCH_INTERVAL
        end

        test "clamps to maximum interval" do
          @source.update_columns(fetch_interval_minutes: 9999)
          adaptive = AdaptiveInterval.new(source: @source, jitter_proc: @no_jitter)

          result = adaptive.compute_next_interval_seconds(content_changed: false, failure: false)

          assert_operator result, :<=, AdaptiveInterval::MAX_FETCH_INTERVAL
        end

        test "respects configured min_interval_minutes" do
          SourceMonitor.configure do |config|
            config.fetching.min_interval_minutes = 15
          end

          @source.update_columns(fetch_interval_minutes: 1)
          adaptive = AdaptiveInterval.new(source: @source, jitter_proc: @no_jitter)

          result = adaptive.compute_next_interval_seconds(content_changed: true, failure: false)

          assert_operator result, :>=, 15 * 60.0
        end

        test "respects configured max_interval_minutes" do
          SourceMonitor.configure do |config|
            config.fetching.max_interval_minutes = 120
          end

          @source.update_columns(fetch_interval_minutes: 9999)
          adaptive = AdaptiveInterval.new(source: @source, jitter_proc: @no_jitter)

          result = adaptive.compute_next_interval_seconds(content_changed: false, failure: false)

          assert_operator result, :<=, 120 * 60.0
        end

        # --- apply_adaptive_interval! ---

        test "sets interval and next_fetch_at when adaptive enabled" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          attributes = {}
          @adaptive.apply_adaptive_interval!(attributes, content_changed: true)

          assert attributes.key?(:fetch_interval_minutes)
          assert attributes.key?(:next_fetch_at)
          assert_operator attributes[:fetch_interval_minutes], :>, 0
          assert_operator attributes[:next_fetch_at], :>, Time.current
        ensure
          travel_back
        end

        test "sets backoff_until on failure" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          attributes = {}
          @adaptive.apply_adaptive_interval!(attributes, content_changed: false, failure: true)

          assert_not_nil attributes[:backoff_until]
          assert_equal attributes[:next_fetch_at], attributes[:backoff_until]
        ensure
          travel_back
        end

        test "clears backoff_until on success" do
          attributes = {}
          @adaptive.apply_adaptive_interval!(attributes, content_changed: true, failure: false)

          assert_nil attributes[:backoff_until]
        end

        test "keeps interval fixed when adaptive disabled" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          @source.update_columns(adaptive_fetching_enabled: false, fetch_interval_minutes: 30)
          adaptive = AdaptiveInterval.new(source: @source, jitter_proc: @no_jitter)

          attributes = {}
          adaptive.apply_adaptive_interval!(attributes, content_changed: true)

          assert_not attributes.key?(:fetch_interval_minutes),
            "interval should not be updated when adaptive disabled"
          assert_equal Time.current + 30.minutes, attributes[:next_fetch_at]
          assert_nil attributes[:backoff_until]
        ensure
          travel_back
        end

        test "does not change interval on failure when adaptive disabled" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          @source.update_columns(adaptive_fetching_enabled: false, fetch_interval_minutes: 45)
          adaptive = AdaptiveInterval.new(source: @source, jitter_proc: @no_jitter)

          attributes = {}
          adaptive.apply_adaptive_interval!(attributes, content_changed: false, failure: true)

          assert_not attributes.key?(:fetch_interval_minutes)
          assert_equal Time.current + 45.minutes, attributes[:next_fetch_at]
          assert_nil attributes[:backoff_until]
        ensure
          travel_back
        end

        # --- jitter ---

        test "jitter_offset returns zero for zero interval" do
          assert_equal 0, @adaptive.jitter_offset(0)
        end

        test "jitter_offset returns zero for negative interval" do
          assert_equal 0, @adaptive.jitter_offset(-100)
        end

        test "jitter_offset uses jitter_proc when provided" do
          adaptive = AdaptiveInterval.new(source: @source, jitter_proc: ->(i) { i * 0.05 })
          assert_in_delta 180.0, adaptive.jitter_offset(3600), 0.01
        end

        # --- interval_minutes_for ---

        test "converts seconds to minutes with minimum of 1" do
          assert_equal 1, @adaptive.interval_minutes_for(30)
          assert_equal 5, @adaptive.interval_minutes_for(300)
          assert_equal 60, @adaptive.interval_minutes_for(3600)
        end

        # --- edge cases ---

        test "handles source with zero fetch_interval_minutes" do
          @source.update_columns(fetch_interval_minutes: 0)
          adaptive = AdaptiveInterval.new(source: @source, jitter_proc: @no_jitter)

          result = adaptive.compute_next_interval_seconds(content_changed: true, failure: false)

          assert_operator result, :>=, AdaptiveInterval::MIN_FETCH_INTERVAL
        end

        test "respects backoff_until when present" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          future_backoff = Time.current + 2.hours
          @source.update_columns(backoff_until: future_backoff)
          adaptive = AdaptiveInterval.new(source: @source.reload, jitter_proc: @no_jitter)

          attributes = {}
          adaptive.apply_adaptive_interval!(attributes, content_changed: true)

          assert_operator attributes[:next_fetch_at], :>=, future_backoff
        ensure
          travel_back
        end
      end
    end
  end
end
