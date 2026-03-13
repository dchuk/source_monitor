# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class ConsecutiveFailuresTest < ActiveSupport::TestCase
      include ActiveSupport::Testing::TimeHelpers

      setup do
        SourceMonitor.reset_configuration!
        SourceMonitor.configure do |config|
          config.health.auto_pause_cooldown_minutes = 30
        end

        @source = create_source!(
          name: "Consecutive Failures Test",
          feed_url: "https://example.com/consecutive-failures.xml"
        )
        @adaptive = FeedFetcher::AdaptiveInterval.new(source: @source, jitter_proc: ->(_) { 0 })
        @updater = FeedFetcher::SourceUpdater.new(source: @source, adaptive_interval: @adaptive)
      end

      # --- Counter increment/reset ---

      test "counter starts at zero" do
        assert_equal 0, @source.consecutive_fetch_failures
      end

      test "counter increments on failure" do
        simulate_failure
        @source.reload
        assert_equal 1, @source.consecutive_fetch_failures
      end

      test "counter increments on successive failures" do
        3.times { simulate_failure }
        @source.reload
        assert_equal 3, @source.consecutive_fetch_failures
      end

      test "counter resets to zero on success" do
        3.times { simulate_failure }
        @source.reload
        assert_equal 3, @source.consecutive_fetch_failures

        simulate_success
        @source.reload
        assert_equal 0, @source.consecutive_fetch_failures
      end

      test "counter resets to zero on 304 not modified" do
        3.times { simulate_failure }
        @source.reload
        assert_equal 3, @source.consecutive_fetch_failures

        simulate_not_modified
        @source.reload
        assert_equal 0, @source.consecutive_fetch_failures
      end

      # --- Auto-pause trigger ---

      test "does not auto-pause at 4 consecutive failures" do
        4.times { simulate_failure }
        @source.reload

        assert_equal 4, @source.consecutive_fetch_failures
        assert_nil @source.auto_paused_until
        assert_not_equal "failing", @source.health_status
      end

      test "auto-pauses at exactly 5 consecutive failures" do
        travel_to Time.current do
          5.times { simulate_failure }
          @source.reload

          assert_equal 5, @source.consecutive_fetch_failures
          assert_equal "failing", @source.health_status
          assert_not_nil @source.auto_paused_until
          assert_not_nil @source.auto_paused_at
          assert_operator @source.auto_paused_until, :>, Time.current
          assert_in_delta @source.auto_paused_until, Time.current + 30.minutes, 2
          assert_equal @source.auto_paused_until, @source.backoff_until
          assert_equal @source.auto_paused_until, @source.next_fetch_at
        end
      end

      test "creates a fetch log when auto-pause triggers" do
        travel_to Time.current do
          5.times { simulate_failure }

          auto_pause_log = @source.fetch_logs.where(error_class: "SourceMonitor::AutoPause").last
          assert_not_nil auto_pause_log
          assert_equal false, auto_pause_log.success
          assert_includes auto_pause_log.error_message, "auto-paused"
          assert_includes auto_pause_log.error_message, "5 consecutive"
          assert_equal "auto_pause", auto_pause_log.metadata["event"]
          assert_equal 5, auto_pause_log.metadata["consecutive_failures"]
        end
      end

      test "does not double-pause if already auto-paused" do
        travel_to Time.current do
          5.times { simulate_failure }
          @source.reload
          first_pause_until = @source.auto_paused_until
          first_pause_at = @source.auto_paused_at

          # More failures should not change auto_paused_until
          2.times { simulate_failure }
          @source.reload

          assert_equal 7, @source.consecutive_fetch_failures
          assert_equal first_pause_until, @source.auto_paused_until
          assert_equal first_pause_at, @source.auto_paused_at
        end
      end

      test "can re-pause after previous auto-pause expires" do
        travel_to Time.current do
          5.times { simulate_failure }
          @source.reload
          first_pause_until = @source.auto_paused_until

          # Simulate the auto-pause expiring
          travel 31.minutes

          # Reset the counter as if a fetch succeeded then failed again
          simulate_success
          5.times { simulate_failure }
          @source.reload

          assert_equal 5, @source.consecutive_fetch_failures
          assert_equal "failing", @source.health_status
          assert_operator @source.auto_paused_until, :>, first_pause_until
        end
      end

      private

      def simulate_failure
        error = TimeoutError.new("connection timed out")
        @updater.update_source_for_failure(error, 5000)
        refresh_updater
      end

      def simulate_success
        response = FeedFetcher::ResponseWrapper.new(status: 200, headers: {}, body: "<rss/>")
        feed = stub_feed
        @updater.update_source_for_success(response, 500, feed, "sig123")
        refresh_updater
      end

      def simulate_not_modified
        response = FeedFetcher::ResponseWrapper.new(status: 304, headers: {}, body: "")
        @updater.update_source_for_not_modified(response, 200)
        refresh_updater
      end

      def refresh_updater
        @source.reload
        @adaptive = FeedFetcher::AdaptiveInterval.new(source: @source, jitter_proc: ->(_) { 0 })
        @updater = FeedFetcher::SourceUpdater.new(source: @source, adaptive_interval: @adaptive)
      end

      def stub_feed
        Class.new do
          def entries
            []
          end

          def self.name
            "Feedjira::Parser::RSS"
          end
        end.new
      end
    end
  end
end
