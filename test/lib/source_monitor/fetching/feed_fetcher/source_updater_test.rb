# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcher
      class SourceUpdaterTest < ActiveSupport::TestCase
        setup do
          @source = create_source!(
            name: "Updater Test",
            fetch_interval_minutes: 60,
            adaptive_fetching_enabled: false
          )
          @adaptive = AdaptiveInterval.new(source: @source, jitter_proc: ->(_) { 0 })
          @updater = SourceUpdater.new(source: @source, adaptive_interval: @adaptive)
        end

        # --- update_source_for_success ---

        test "resets failure state on success" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          @source.update_columns(
            failure_count: 3,
            consecutive_fetch_failures: 3,
            last_error: "previous error",
            last_error_at: 1.hour.ago
          )

          response = stub_response(200, { "ETag" => '"abc123"' })
          @updater.update_source_for_success(response, 150, nil, nil)

          @source.reload
          assert_equal 0, @source.failure_count
          assert_equal 0, @source.consecutive_fetch_failures
          assert_nil @source.last_error
          assert_nil @source.last_error_at
          assert_equal Time.current, @source.last_fetched_at
          assert_equal 150, @source.last_fetch_duration_ms
          assert_equal 200, @source.last_http_status
        ensure
          travel_back
        end

        test "updates etag from response headers" do
          response = stub_response(200, { "ETag" => '"new-etag"' })
          @updater.update_source_for_success(response, 100, nil, nil)

          @source.reload
          assert_equal '"new-etag"', @source.etag
        end

        test "updates last_modified from response headers" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          last_mod = "Sat, 01 Jun 2024 10:00:00 GMT"
          response = stub_response(200, { "Last-Modified" => last_mod })
          @updater.update_source_for_success(response, 100, nil, nil)

          @source.reload
          assert_equal Time.httpdate(last_mod), @source.last_modified
        ensure
          travel_back
        end

        test "sets next_fetch_at on success" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          response = stub_response(200)
          @updater.update_source_for_success(response, 100, nil, nil)

          @source.reload
          assert_not_nil @source.next_fetch_at
          assert_operator @source.next_fetch_at, :>, Time.current
        ensure
          travel_back
        end

        test "resets retry state on success" do
          @source.update_columns(
            fetch_retry_attempt: 2,
            fetch_circuit_opened_at: 1.hour.ago,
            fetch_circuit_until: 1.hour.from_now
          )

          response = stub_response(200)
          @updater.update_source_for_success(response, 100, nil, nil)

          @source.reload
          assert_equal 0, @source.fetch_retry_attempt
          assert_nil @source.fetch_circuit_opened_at
          assert_nil @source.fetch_circuit_until
        end

        test "stores feed_signature in metadata" do
          response = stub_response(200)
          @updater.update_source_for_success(response, 100, nil, "sig123")

          @source.reload
          assert_equal "sig123", @source.metadata["last_feed_signature"]
        end

        test "stores entries_digest in metadata" do
          response = stub_response(200)
          @updater.update_source_for_success(response, 100, nil, nil, entries_digest: "digest456")

          @source.reload
          assert_equal "digest456", @source.metadata["last_entries_digest"]
        end

        # --- update_source_for_not_modified ---

        test "handles 304 not modified response" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          @source.update_columns(failure_count: 1, last_error: "old error")

          response = stub_response(304, { "ETag" => '"same-etag"' })
          @updater.update_source_for_not_modified(response, 50)

          @source.reload
          assert_equal 0, @source.failure_count
          assert_nil @source.last_error
          assert_equal 304, @source.last_http_status
          assert_equal '"same-etag"', @source.etag
          assert_not_nil @source.next_fetch_at
        ensure
          travel_back
        end

        # --- update_source_for_failure ---

        test "increments failure counts on failure" do
          error = TimeoutError.new("timed out")
          @updater.update_source_for_failure(error, 5000)

          @source.reload
          assert_equal 1, @source.failure_count
          assert_equal 1, @source.consecutive_fetch_failures
          assert_equal "timed out", @source.last_error
          assert_not_nil @source.last_error_at
        end

        test "accumulates failure count across multiple failures" do
          @source.update_columns(failure_count: 2, consecutive_fetch_failures: 2)

          error = ConnectionError.new("refused")
          @updater.update_source_for_failure(error, 100)

          @source.reload
          assert_equal 3, @source.failure_count
          assert_equal 3, @source.consecutive_fetch_failures
        end

        test "records http_status from error response" do
          response = stub_response(503)
          error = HTTPError.new(status: 503, response: response)
          @updater.update_source_for_failure(error, 200)

          @source.reload
          assert_equal 503, @source.last_http_status
        end

        # --- create_fetch_log ---

        test "creates successful fetch log with correct attributes" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          started_at = Time.current
          response = stub_response(200)

          log = @updater.create_fetch_log(
            response: response,
            duration_ms: 250,
            started_at: started_at,
            success: true,
            items_created: 5,
            items_updated: 2,
            items_failed: 1
          )

          assert log.persisted?
          assert_equal @source, log.source
          assert log.success
          assert_equal 250, log.duration_ms
          assert_equal 200, log.http_status
          assert_equal 5, log.items_created
          assert_equal 2, log.items_updated
          assert_equal 1, log.items_failed
          assert_equal started_at, log.started_at
          assert_equal started_at + 0.25, log.completed_at
        ensure
          travel_back
        end

        test "creates failed fetch log with error details" do
          started_at = Time.current
          response = stub_response(500)
          error = HTTPError.new(status: 500)

          log = @updater.create_fetch_log(
            response: response,
            duration_ms: 100,
            started_at: started_at,
            success: false,
            error: error
          )

          assert log.persisted?
          assert_not log.success
          assert_equal "SourceMonitor::Fetching::HTTPError", log.error_class
          assert_equal "HTTP 500", log.error_message
          assert_equal "network", log.error_category
        end

        test "records feed size and items in feed" do
          feed = Struct.new(:entries).new([1, 2, 3])
          body = "<rss>sample body</rss>"

          log = @updater.create_fetch_log(
            response: stub_response(200),
            duration_ms: 100,
            started_at: Time.current,
            success: true,
            feed: feed,
            body: body
          )

          assert_equal body.bytesize, log.feed_size_bytes
          assert_equal 3, log.items_in_feed
        end

        # --- feed_signature_changed? ---

        test "returns false when feed_signature is blank" do
          assert_not @updater.feed_signature_changed?(nil)
          assert_not @updater.feed_signature_changed?("")
        end

        test "returns true when signature differs from stored" do
          @source.update_columns(metadata: { "last_feed_signature" => "old_sig" })

          assert @updater.feed_signature_changed?("new_sig")
        end

        test "returns false when signature matches stored" do
          @source.update_columns(metadata: { "last_feed_signature" => "same_sig" })

          assert_not @updater.feed_signature_changed?("same_sig")
        end

        # --- elapsed_ms ---

        test "computes elapsed milliseconds" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          started_at = Time.current - 1.5.seconds
          result = @updater.elapsed_ms(started_at)

          assert_equal 1500, result
        ensure
          travel_back
        end

        # --- parse_http_time ---

        test "parses valid HTTP date" do
          result = @updater.parse_http_time("Sat, 01 Jun 2024 10:00:00 GMT")

          assert_kind_of Time, result
          assert_equal 2024, result.year
          assert_equal 6, result.month
        end

        test "returns nil for blank value" do
          assert_nil @updater.parse_http_time(nil)
          assert_nil @updater.parse_http_time("")
        end

        test "returns nil for invalid HTTP date" do
          assert_nil @updater.parse_http_time("not-a-date")
        end

        # --- edge case: failed source recovers on success ---

        test "fully recovers from failed state on success" do
          travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

          @source.update_columns(
            failure_count: 5,
            consecutive_fetch_failures: 5,
            last_error: "Connection refused",
            last_error_at: 30.minutes.ago,
            fetch_retry_attempt: 3,
            fetch_circuit_opened_at: 1.hour.ago,
            fetch_circuit_until: 30.minutes.from_now,
            last_http_status: 500
          )

          response = stub_response(200, { "ETag" => '"recovered"' })
          @updater.update_source_for_success(response, 200, nil, "new_sig")

          @source.reload
          assert_equal 0, @source.failure_count
          assert_equal 0, @source.consecutive_fetch_failures
          assert_nil @source.last_error
          assert_nil @source.last_error_at
          assert_equal 0, @source.fetch_retry_attempt
          assert_nil @source.fetch_circuit_opened_at
          assert_nil @source.fetch_circuit_until
          assert_equal 200, @source.last_http_status
          assert_equal '"recovered"', @source.etag
        ensure
          travel_back
        end

        private

        def stub_response(status, headers = {})
          ResponseWrapper.new(status: status, headers: headers, body: "")
        end
      end
    end
  end
end
