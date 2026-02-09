# frozen_string_literal: true

require "test_helper"
require "uri"
require "digest"

module SourceMonitor
  module Fetching
    class FeedFetcherTest < ActiveSupport::TestCase
      test "continues processing when an item creation fails" do
        source = build_source(
          name: "RSS Sample with failure",
          feed_url: "https://www.ruby-lang.org/en/feeds/news.rss"
        )

        singleton = SourceMonitor::Items::ItemCreator.singleton_class
        call_count = 0
        error_message = "forced failure"
        result = nil

        singleton.alias_method :call_without_stub, :call
        singleton.define_method(:call) do |source:, entry:|
          call_count += 1
          if call_count == 1
            raise StandardError, error_message
          else
            call_without_stub(source:, entry:)
          end
        end

        begin
          VCR.use_cassette("source_monitor/fetching/rss_success") do
            result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
          end
        ensure
          singleton.alias_method :call, :call_without_stub
          singleton.remove_method :call_without_stub
        end

        assert_equal :fetched, result.status
        processing = result.item_processing
        assert_equal 1, processing.failed
        assert processing.created.positive?
        assert_equal call_count - 1, processing.created
        assert_equal 0, processing.updated

        source.reload
        assert_equal call_count - 1, source.items_count

        log = source.fetch_logs.order(:created_at).last
        assert_equal call_count - 1, log.items_created
        assert_equal 0, log.items_updated
        assert_equal 1, log.items_failed
        assert log.metadata["item_errors"].present?
        error_entry = log.metadata["item_errors"].first
        assert_equal error_message, error_entry["error_message"]
      end

      test "fetches an RSS feed and records log entries" do
        source = build_source(
          name: "RSS Sample",
          feed_url: "https://www.ruby-lang.org/en/feeds/news.rss"
        )

        finish_payloads = []
        result = nil
        ActiveSupport::Notifications.subscribed(
          ->(_name, _start, _finish, _id, payload) { finish_payloads << payload },
          "source_monitor.fetch.finish"
        ) do
          VCR.use_cassette("source_monitor/fetching/rss_success") do
            result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
          end
        end

        assert_equal :fetched, result.status
        assert_kind_of Feedjira::Parser::RSS, result.feed
        processing = result.item_processing
        refute_nil processing
        assert_equal result.feed.entries.size, processing.created
        assert_equal 0, processing.updated
        assert_equal 0, processing.failed

        assert_equal result.feed.entries.size, SourceMonitor::Item.where(source: source).count
        assert_equal result.feed.entries.size, source.reload.items_count

        source.reload
        assert_equal 200, source.last_http_status
        assert_equal "rss", source.feed_format
        assert source.etag.present?

        log = source.fetch_logs.order(:created_at).last
        assert log.success
        assert_equal 200, log.http_status
        assert log.feed_size_bytes.positive?
        assert_equal result.feed.entries.size, log.items_in_feed
        assert_equal Feedjira::Parser::RSS.name, log.metadata["parser"]
        assert_equal result.feed.entries.size, log.items_created
        assert_equal 0, log.items_updated
        assert_equal 0, log.items_failed
        assert_nil log.metadata["item_errors"]

        finish_payload = finish_payloads.last
        assert finish_payload[:success]
        assert_equal :fetched, finish_payload[:status]
        assert_equal 200, finish_payload[:http_status]
        assert_equal source.id, finish_payload[:source_id]
        assert_equal Feedjira::Parser::RSS.name, finish_payload[:parser]
        assert_equal result.feed.entries.size, finish_payload[:items_created]
        assert_equal 0, finish_payload[:items_updated]
        assert_equal 0, finish_payload[:items_failed]
      end

      test "reuses etag and handles 304 not modified responses" do
        feed_body = File.read(file_fixture("feeds/rss_sample.xml"))
        url = "https://example.com/rss.xml"

        source = build_source(name: "With ETag", feed_url: url)

        stub_request(:get, url)
          .to_return(
            status: 200,
            body: feed_body,
            headers: {
              "Content-Type" => "application/rss+xml",
              "ETag" => '"abcd1234"'
            }
          )

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        assert_equal :fetched, result.status
        assert_equal result.feed.entries.size, result.item_processing.created

        source.reload
        assert_equal '"abcd1234"', source.etag

        stub_request(:get, url)
          .with(headers: { "If-None-Match" => '"abcd1234"' })
          .to_return(status: 304, headers: { "ETag" => '"abcd1234"' })

        second_result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :not_modified, second_result.status
        refute_nil second_result.item_processing
        assert_equal 0, second_result.item_processing.created
        assert_equal 0, second_result.item_processing.updated
        assert_equal 0, second_result.item_processing.failed

        source.reload
        assert_equal 304, source.last_http_status
        assert_equal '"abcd1234"', source.etag

        log = source.fetch_logs.order(:created_at).last
        assert log.success
        assert_equal 304, log.http_status
        assert_nil log.items_in_feed
        assert_equal 0, log.items_created
        assert_equal 0, log.items_updated
        assert_equal 0, log.items_failed

        source.reload
        assert_equal 0, source.failure_count
        assert_nil source.last_error
        assert_nil source.last_error_at
      end

      test "parses rss atom and json feeds via feedjira" do
        feeds = {
          rss:  {
            url: "https://www.ruby-lang.org/en/feeds/news.rss",
            parser: Feedjira::Parser::RSS
          },
          atom: {
            url: "https://go.dev/blog/feed.atom",
            parser: Feedjira::Parser::Atom
          },
          json: {
            url: "https://daringfireball.net/feeds/json",
            parser: Feedjira::Parser::JSONFeed
          }
        }

        feeds.each do |format, data|
          source = build_source(name: "#{format} feed", feed_url: data[:url])

          result = nil
          VCR.use_cassette("source_monitor/fetching/#{format}_success") do
            result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
          end

          assert_equal :fetched, result.status
          assert_kind_of data[:parser], result.feed
          expected_format = format == :json ? "json_feed" : format.to_s
          assert_equal expected_format, source.reload.feed_format
        end
      end

      test "records timeout failures and emits failure notifications" do
        url = "https://example.com/rss-timeout.xml"
        source = build_source(name: "Timeout Source", feed_url: url)

        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("execution expired"))

        finish_payloads = []
        result = ActiveSupport::Notifications.subscribed(
          ->(_name, _start, _finish, _id, payload) { finish_payloads << payload },
          "source_monitor.fetch.finish"
        ) do
          FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        end

        assert_equal :failed, result.status
        assert_kind_of SourceMonitor::Fetching::TimeoutError, result.error

        source.reload
        assert_equal 1, source.failure_count
        assert_nil source.last_http_status
        assert_equal result.error.message, source.last_error
        assert source.last_error_at.present?

        log = source.fetch_logs.order(:created_at).last
        refute log.success
        assert_nil log.http_status
        assert_equal "SourceMonitor::Fetching::TimeoutError", log.error_class
        assert_equal result.error.message, log.error_message
        assert_equal "timeout", log.metadata["error_code"]

        payload = finish_payloads.last
        refute payload[:success]
        assert_equal :failed, payload[:status]
        assert_equal "SourceMonitor::Fetching::TimeoutError", payload[:error_class]
        assert_equal source.id, payload[:source_id]
        assert_equal "timeout", payload[:error_code]
      end

      test "records http failures with status codes" do
        url = "https://example.com/missing-feed.xml"
        source = build_source(name: "Missing Feed", feed_url: url)

        stub_request(:get, url).to_return(status: 404, body: "Not Found", headers: { "Content-Type" => "text/plain" })

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        assert_kind_of SourceMonitor::Fetching::HTTPError, result.error
        assert_equal 404, result.error.http_status

        source.reload
        assert_equal 1, source.failure_count
        assert_equal 404, source.last_http_status
        assert source.last_error.include?("404")

        log = source.fetch_logs.order(:created_at).last
        refute log.success
        assert_equal 404, log.http_status
        assert_equal "SourceMonitor::Fetching::HTTPError", log.error_class
        assert_equal "http_error", log.metadata["error_code"]
        assert_match(/404/, log.error_message)
      end

      test "records parsing failures when feed is malformed" do
        url = "https://example.com/bad-feed.xml"
        source = build_source(name: "Bad Feed", feed_url: url)

        stub_request(:get, url).to_return(status: 200, body: "not actually a feed", headers: { "Content-Type" => "text/plain" })

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        assert_kind_of SourceMonitor::Fetching::ParsingError, result.error

        source.reload
        assert_equal 1, source.failure_count
        assert_equal 200, source.last_http_status
        assert source.last_error.present?

        log = source.fetch_logs.order(:created_at).last
        refute log.success
        assert_equal 200, log.http_status
        assert_equal "SourceMonitor::Fetching::ParsingError", log.error_class
        assert_equal "parsing", log.metadata["error_code"]
        assert_match(/parse/i, log.error_message)
      end

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

      private

      def build_source(name:, feed_url:, fetch_interval_minutes: 360, adaptive_fetching_enabled: true)
        create_source!(
          name: name,
          feed_url: feed_url,
          fetch_interval_minutes: fetch_interval_minutes,
          adaptive_fetching_enabled: adaptive_fetching_enabled
        )
      end

      def body_digest(body)
        Digest::SHA256.hexdigest(body)
      end
    end
  end
end
