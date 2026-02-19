# frozen_string_literal: true

require "test_helper"
require "faraday"
require "uri"
require "digest"
require_relative "feed_fetcher_test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcherRetryCircuitTest < ActiveSupport::TestCase
      include FeedFetcherTestHelper

      test "reset_retry_state clears retry attempt and circuit fields on success" do
        url = "https://example.com/retry-reset.xml"
        source = build_source(name: "Retry Reset", feed_url: url)
        source.update_columns(fetch_retry_attempt: 2, fetch_circuit_opened_at: 1.hour.ago, fetch_circuit_until: 1.hour.from_now)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal 0, source.fetch_retry_attempt
        assert_nil source.fetch_circuit_opened_at
        assert_nil source.fetch_circuit_until
      end

      test "reset_retry_state clears circuit fields on 304 not modified" do
        url = "https://example.com/retry-reset-304.xml"
        source = build_source(name: "Retry Reset 304", feed_url: url)
        source.update_columns(
          fetch_retry_attempt: 1,
          fetch_circuit_opened_at: 1.hour.ago,
          fetch_circuit_until: 1.hour.from_now,
          etag: '"xyz"'
        )

        stub_request(:get, url)
          .to_return(status: 304, headers: { "ETag" => '"xyz"' })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal 0, source.fetch_retry_attempt
        assert_nil source.fetch_circuit_opened_at
        assert_nil source.fetch_circuit_until
      end

      test "apply_retry_strategy sets retry state when retryable" do
        url = "https://example.com/retry-strategy.xml"
        source = build_source(name: "Retry Strategy", feed_url: url)
        # TimeoutError allows 2 attempts with 2.minute wait
        source.update_columns(fetch_retry_attempt: 0)

        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("timed out"))

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        assert result.retry_decision.retry?
        refute result.retry_decision.open_circuit?
        assert_equal 1, result.retry_decision.next_attempt

        source.reload
        assert_equal 1, source.fetch_retry_attempt
        assert_nil source.fetch_circuit_opened_at
        assert_nil source.fetch_circuit_until
      end

      test "apply_retry_strategy opens circuit when retries exhausted" do
        travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

        url = "https://example.com/circuit-open.xml"
        source = build_source(name: "Circuit Open", feed_url: url)
        # TimeoutError allows 2 attempts; set retry_attempt to 2 so next exceeds limit
        source.update_columns(fetch_retry_attempt: 2)

        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("timed out"))

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        refute result.retry_decision.retry?
        assert result.retry_decision.open_circuit?

        source.reload
        assert_equal 0, source.fetch_retry_attempt
        assert source.fetch_circuit_opened_at.present?
        assert source.fetch_circuit_until.present?
        assert source.fetch_circuit_until > Time.current
        assert_equal source.fetch_circuit_until, source.next_fetch_at
        assert_equal source.fetch_circuit_until, source.backoff_until
      ensure
        travel_back
      end

      test "apply_retry_strategy sets next_fetch_at to earliest of adaptive interval and retry wait" do
        travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

        url = "https://example.com/retry-next-fetch.xml"
        source = build_source(name: "Retry Next Fetch", feed_url: url, fetch_interval_minutes: 60)
        source.update_columns(fetch_retry_attempt: 0)

        # ConnectionError: 3 attempts, 5 minute wait
        stub_request(:get, url).to_raise(Faraday::ConnectionFailed.new("connection refused"))

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        assert result.retry_decision.retry?

        source.reload
        # retry wait is 5 minutes, adaptive failure interval is 60*1.5=90 minutes
        # next_fetch_at should be min of adaptive_next and retry_at
        assert source.backoff_until.present?
        assert source.next_fetch_at <= source.backoff_until
      ensure
        travel_back
      end

      test "apply_retry_strategy handles policy error gracefully" do
        url = "https://example.com/policy-error.xml"
        source = build_source(name: "Policy Error", feed_url: url)

        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("timed out"))

        # Simulate RetryPolicy raising an error
        SourceMonitor::Fetching::RetryPolicy.stub(:new, ->(**_) { raise StandardError, "policy exploded" }) do
          result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

          assert_equal :failed, result.status
          assert_nil result.retry_decision

          source.reload
          assert_equal 0, source.fetch_retry_attempt
          assert_nil source.fetch_circuit_opened_at
          assert_nil source.fetch_circuit_until
        end
      end
    end
  end
end
