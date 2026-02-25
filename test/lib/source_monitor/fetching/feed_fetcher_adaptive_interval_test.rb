# frozen_string_literal: true

require "test_helper"
require "faraday"
require "uri"
require "digest"
require_relative "feed_fetcher_test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcherAdaptiveIntervalTest < ActiveSupport::TestCase
      include FeedFetcherTestHelper

      test "decreases fetch interval and clears backoff when feed content changes" do
        travel_to Time.zone.parse("2024-01-01 10:00:00 UTC")

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        url = "https://example.com/rss.xml"

        source = build_source(name: "Adaptive", feed_url: url, fetch_interval_minutes: 60)

        stub_request(:get, url)
          .to_return(status: 200, body:, headers: { "Content-Type" => "application/rss+xml" })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload

        assert_equal 45, source.fetch_interval_minutes
        assert_equal Time.current + 45.minutes, source.next_fetch_at
        assert_nil source.backoff_until
        refute source.metadata.key?("dynamic_fetch_interval_seconds")
        assert source.metadata.key?("last_feed_signature")
      ensure
        travel_back
      end

      test "uses configured adaptive interval settings" do
        SourceMonitor.reset_configuration!

        SourceMonitor.configure do |config|
          config.fetching.min_interval_minutes = 10
          config.fetching.max_interval_minutes = 120
          config.fetching.increase_factor = 2.0
          config.fetching.decrease_factor = 0.5
          config.fetching.failure_increase_factor = 3.0
          config.fetching.jitter_percent = 0
        end

        travel_to Time.zone.parse("2024-02-01 09:00:00 UTC")

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        url = "https://example.com/configurable.xml"

        source = build_source(name: "Configurable", feed_url: url, fetch_interval_minutes: 60)

        stub_request(:get, url)
          .to_return(status: 200, body:, headers: { "Content-Type" => "application/rss+xml", "ETag" => "abc" })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal 30, source.fetch_interval_minutes, "expected decrease factor to halve the interval"

        stub_request(:get, url)
          .to_return(status: 200, body:, headers: { "Content-Type" => "application/rss+xml", "ETag" => "abc" })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal 60, source.fetch_interval_minutes, "expected increase factor to double interval up to max"

        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("timed out"))

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal 120, source.fetch_interval_minutes, "expected failure multiplier to respect max bound"
        assert_equal source.next_fetch_at, source.backoff_until
      ensure
        SourceMonitor.reset_configuration!
        travel_back
      end

      test "increases interval when feed content unchanged" do
        travel_to Time.zone.parse("2024-01-01 09:00:00 UTC")

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        url = "https://example.com/rss.xml"

        source = build_source(name: "Adaptive", feed_url: url, fetch_interval_minutes: 60)

        stub_request(:get, url)
          .to_return(status: 200, body:, headers: { "Content-Type" => "application/rss+xml", "ETag" => "abc" })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal 45, source.fetch_interval_minutes

        stub_request(:get, url)
          .to_return(status: 200, body:, headers: { "Content-Type" => "application/rss+xml", "ETag" => "abc" })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        expected_minutes = (45 * SourceMonitor::Fetching::FeedFetcher::INCREASE_FACTOR).round
        assert_equal expected_minutes, source.fetch_interval_minutes
        expected_seconds = 45 * 60 * SourceMonitor::Fetching::FeedFetcher::INCREASE_FACTOR
        assert_in_delta expected_seconds, source.next_fetch_at - Time.current, 1e-6
      ensure
        travel_back
      end

      test "respects min and max interval bounds" do
        travel_to Time.zone.parse("2024-01-01 08:00:00 UTC")

        url = "https://example.com/minmax.xml"
        body = "<rss><channel><title>Test</title><item><title>One</title><link>https://example.com/items/1</link><guid>1</guid></item></channel></rss>"

        source = build_source(name: "Min", feed_url: url, fetch_interval_minutes: 1)

        stub_request(:get, url)
          .to_return(status: 200, body:, headers: { "Content-Type" => "application/rss+xml" })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        source.reload

        min_minutes = (SourceMonitor::Fetching::FeedFetcher::MIN_FETCH_INTERVAL / 60.0).round
        assert_equal min_minutes, source.fetch_interval_minutes

        source.update!(fetch_interval_minutes: 200 * 60)

        stub_request(:get, url)
          .to_return(status: 304, headers: { "Content-Type" => "application/rss+xml" })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        source.reload

        max_minutes = (SourceMonitor::Fetching::FeedFetcher::MAX_FETCH_INTERVAL / 60.0).round
        assert_equal max_minutes, source.fetch_interval_minutes
      ensure
        travel_back
      end

      test "increases interval and sets backoff on failure" do
        travel_to Time.zone.parse("2024-01-01 07:00:00 UTC")

        url = "https://example.com/failure.xml"
        source = build_source(name: "Failure", feed_url: url, fetch_interval_minutes: 60)

        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("boom"))

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal 1, source.failure_count
        expected_minutes = (60 * SourceMonitor::Fetching::FeedFetcher::FAILURE_INCREASE_FACTOR).round
        assert_equal expected_minutes, source.fetch_interval_minutes
        assert_equal source.next_fetch_at, source.backoff_until
      ensure
        travel_back
      end

      test "keeps interval fixed when adaptive fetching is disabled" do
        travel_to Time.zone.parse("2024-01-02 12:00:00 UTC")

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        url = "https://example.com/static.xml"

        source = build_source(name: "Static", feed_url: url, fetch_interval_minutes: 60, adaptive_fetching_enabled: false)

        stub_request(:get, url)
          .to_return(status: 200, body:, headers: { "Content-Type" => "application/rss+xml" })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal 60, source.fetch_interval_minutes
        assert_equal Time.current + 60.minutes, source.next_fetch_at
        assert_nil source.backoff_until
        assert_equal body_digest(body), source.metadata["last_feed_signature"]
        refute source.metadata.key?("dynamic_fetch_interval_seconds")

        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("boom"))

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal 60, source.fetch_interval_minutes
        assert_equal Time.current + 60.minutes, source.next_fetch_at
        assert_nil source.backoff_until
        refute source.metadata.key?("dynamic_fetch_interval_seconds")
      ensure
        travel_back
      end

      test "fixed-interval sources get jitter when jitter_percent is non-zero" do
        SourceMonitor.reset_configuration!

        travel_to Time.zone.parse("2024-03-01 10:00:00 UTC")

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        url = "https://example.com/fixed-jitter.xml"

        source = build_source(name: "FixedJitter", feed_url: url, fetch_interval_minutes: 60, adaptive_fetching_enabled: false)

        stub_request(:get, url)
          .to_return(status: 200, body:, headers: { "Content-Type" => "application/rss+xml" })

        FeedFetcher.new(source: source).call

        source.reload
        expected_base = Time.current + 60.minutes
        max_jitter = 60.minutes.to_f * 0.1

        assert_in_delta expected_base.to_f, source.next_fetch_at.to_f, max_jitter,
          "next_fetch_at should be within ±10% jitter of 60 minutes"
        assert_equal 60, source.fetch_interval_minutes, "fixed interval should not change"
      ensure
        SourceMonitor.reset_configuration!
        travel_back
      end

      test "fixed-interval jitter respects jitter_proc override" do
        travel_to Time.zone.parse("2024-03-01 11:00:00 UTC")

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        url = "https://example.com/fixed-jitter-proc.xml"

        source = build_source(name: "FixedJitterProc", feed_url: url, fetch_interval_minutes: 60, adaptive_fetching_enabled: false)

        stub_request(:get, url)
          .to_return(status: 200, body:, headers: { "Content-Type" => "application/rss+xml" })

        FeedFetcher.new(source: source, jitter: ->(interval) { interval * 0.05 }).call

        source.reload
        expected_seconds = 3600 + (3600 * 0.05)
        assert_equal Time.current + expected_seconds, source.next_fetch_at,
          "next_fetch_at should reflect the 5% jitter_proc offset"
        assert_equal 60, source.fetch_interval_minutes
      ensure
        travel_back
      end

      test "fixed-interval with zero jitter_percent has no jitter" do
        SourceMonitor.reset_configuration!

        SourceMonitor.configure do |config|
          config.fetching.jitter_percent = 0
        end

        travel_to Time.zone.parse("2024-03-01 12:00:00 UTC")

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        url = "https://example.com/fixed-no-jitter.xml"

        source = build_source(name: "FixedNoJitter", feed_url: url, fetch_interval_minutes: 60, adaptive_fetching_enabled: false)

        stub_request(:get, url)
          .to_return(status: 200, body:, headers: { "Content-Type" => "application/rss+xml" })

        FeedFetcher.new(source: source).call

        source.reload
        assert_equal Time.current + 60.minutes, source.next_fetch_at,
          "next_fetch_at should be exactly 60 minutes with zero jitter"
        assert_equal 60, source.fetch_interval_minutes
      ensure
        SourceMonitor.reset_configuration!
        travel_back
      end
    end
  end
end
