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

      # ── Task 1: Retry strategy and circuit breaker transitions ──

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

      # ── Task 2: Faraday error wrapping and connection failures ──

      test "wraps Faraday::TimeoutError as TimeoutError" do
        url = "https://example.com/faraday-timeout.xml"
        source = build_source(name: "Faraday Timeout", feed_url: url)

        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("execution expired"))

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        assert_kind_of SourceMonitor::Fetching::TimeoutError, result.error
        assert_equal "execution expired", result.error.message
        assert_kind_of Faraday::TimeoutError, result.error.original_error
      end

      test "wraps Faraday::ConnectionFailed as ConnectionError" do
        url = "https://example.com/faraday-conn.xml"
        source = build_source(name: "Faraday Conn", feed_url: url)

        stub_request(:get, url).to_raise(Faraday::ConnectionFailed.new("connection refused"))

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        assert_kind_of SourceMonitor::Fetching::ConnectionError, result.error
        assert_equal "connection refused", result.error.message
        assert_kind_of Faraday::ConnectionFailed, result.error.original_error
      end

      test "wraps Faraday::SSLError as ConnectionError" do
        url = "https://example.com/faraday-ssl.xml"
        source = build_source(name: "Faraday SSL", feed_url: url)

        stub_request(:get, url).to_raise(Faraday::SSLError.new("SSL certificate problem"))

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        assert_kind_of SourceMonitor::Fetching::ConnectionError, result.error
        assert_match(/SSL certificate problem/, result.error.message)
      end

      test "wraps generic Faraday::Error as FetchError" do
        url = "https://example.com/faraday-generic.xml"
        source = build_source(name: "Faraday Generic", feed_url: url)

        stub_request(:get, url).to_raise(Faraday::Error.new("something unexpected"))

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        assert_kind_of SourceMonitor::Fetching::FetchError, result.error
        assert_equal "something unexpected", result.error.message
      end

      test "wraps unexpected StandardError as UnexpectedResponseError" do
        url = "https://example.com/unexpected-error.xml"
        source = build_source(name: "Unexpected", feed_url: url)

        # Use a custom client that raises a StandardError during get
        error_client = Object.new
        error_client.define_singleton_method(:get) do |_url|
          raise StandardError, "totally unexpected"
        end

        result = FeedFetcher.new(source: source, client: error_client, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        assert_kind_of SourceMonitor::Fetching::UnexpectedResponseError, result.error
        assert_equal "totally unexpected", result.error.message
        assert_kind_of StandardError, result.error.original_error
      end

      test "build_http_error_from_faraday constructs HTTPError with status from Faraday::ClientError" do
        url = "https://example.com/client-error.xml"
        source = build_source(name: "Client Error", feed_url: url)

        stub_request(:get, url).to_return(status: 403, body: "Forbidden", headers: { "Content-Type" => "text/plain" })

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        assert_kind_of SourceMonitor::Fetching::HTTPError, result.error
        assert_equal 403, result.error.http_status
      end

      test "re-raises existing FetchError subclasses without double-wrapping" do
        url = "https://example.com/already-timeout.xml"
        source = build_source(name: "Already Timeout", feed_url: url)

        # Stub to raise Faraday::TimeoutError, which gets wrapped once as TimeoutError
        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("timed out"))

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        # The error should be a TimeoutError, not a FetchError wrapping a TimeoutError
        assert_kind_of SourceMonitor::Fetching::TimeoutError, result.error
        refute_kind_of SourceMonitor::Fetching::UnexpectedResponseError, result.error
      end

      # ── Task 3: Last-Modified header handling and request headers ──

      test "sends If-Modified-Since header when source has last_modified" do
        url = "https://example.com/last-modified.xml"
        last_mod = Time.utc(2024, 3, 15, 10, 30, 0)
        source = build_source(name: "Last Modified", feed_url: url)
        source.update_columns(last_modified: last_mod)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        stub_request(:get, url)
          .with(headers: { "If-Modified-Since" => last_mod.httpdate })
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        assert_equal :fetched, result.status
      end

      test "sends both If-None-Match and If-Modified-Since when both present" do
        url = "https://example.com/both-headers.xml"
        last_mod = Time.utc(2024, 3, 15, 10, 30, 0)
        source = build_source(name: "Both Headers", feed_url: url)
        source.update_columns(etag: '"etag123"', last_modified: last_mod)

        stub_request(:get, url)
          .with(headers: {
            "If-None-Match" => '"etag123"',
            "If-Modified-Since" => last_mod.httpdate
          })
          .to_return(status: 304, headers: { "ETag" => '"etag123"' })

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        assert_equal :not_modified, result.status
      end

      test "includes custom_headers in request" do
        url = "https://example.com/custom-headers.xml"
        source = build_source(name: "Custom Headers", feed_url: url)
        source.update!(custom_headers: { "X-Api-Key" => "secret123", "Accept" => "application/rss+xml" })

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        stub_request(:get, url)
          .with(headers: { "X-Api-Key" => "secret123", "Accept" => "application/rss+xml" })
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        assert_equal :fetched, result.status
      end

      test "updates source last_modified from response Last-Modified header on success" do
        travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

        url = "https://example.com/update-last-modified.xml"
        source = build_source(name: "Update Last Modified", feed_url: url)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        last_mod_str = Time.utc(2024, 5, 20, 8, 0, 0).httpdate

        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: {
            "Content-Type" => "application/rss+xml",
            "Last-Modified" => last_mod_str
          })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal Time.httpdate(last_mod_str), source.last_modified
      ensure
        travel_back
      end

      test "updates source last_modified from response header on 304" do
        url = "https://example.com/last-modified-304.xml"
        source = build_source(name: "Last Modified 304", feed_url: url)
        source.update_columns(etag: '"abc"')

        last_mod_str = Time.utc(2024, 5, 20, 8, 0, 0).httpdate

        stub_request(:get, url)
          .to_return(status: 304, headers: {
            "ETag" => '"abc"',
            "Last-Modified" => last_mod_str
          })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal Time.httpdate(last_mod_str), source.last_modified
      end

      test "ignores unparseable Last-Modified header" do
        url = "https://example.com/bad-last-modified.xml"
        source = build_source(name: "Bad Last Modified", feed_url: url)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: {
            "Content-Type" => "application/rss+xml",
            "Last-Modified" => "not-a-valid-date"
          })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_nil source.last_modified
      end

      test "updates etag from response on success" do
        url = "https://example.com/etag-update.xml"
        source = build_source(name: "ETag Update", feed_url: url)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: {
            "Content-Type" => "application/rss+xml",
            "ETag" => '"new-etag-value"'
          })

        FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        source.reload
        assert_equal '"new-etag-value"', source.etag
      end

      # ── Task 4: Entry processing edge cases and error normalization ──

      test "process_feed_entries returns empty result when feed has no entries method" do
        url = "https://example.com/no-entries.xml"
        source = build_source(name: "No Entries", feed_url: url)

        # Stub with a body that parses to a feed without entries
        body = "<rss version='2.0'><channel><title>Empty</title></channel></rss>"
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :fetched, result.status
        assert_equal 0, result.item_processing.created
        assert_equal 0, result.item_processing.updated
        assert_equal 0, result.item_processing.failed
        assert_empty result.item_processing.errors
      end

      test "normalize_item_error captures guid and title from entry" do
        url = "https://example.com/error-normalize.xml"
        source = build_source(name: "Error Normalize", feed_url: url)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        error_message = "duplicate key"
        singleton = SourceMonitor::Items::ItemCreator.singleton_class
        singleton.alias_method :call_without_stub, :call
        singleton.define_method(:call) do |source:, entry:|
          raise StandardError, error_message
        end

        begin
          result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

          assert_equal :fetched, result.status
          assert result.item_processing.failed.positive?
          assert result.item_processing.errors.any?

          error_entry = result.item_processing.errors.first
          assert_equal error_message, error_entry[:error_message]
          assert_equal "StandardError", error_entry[:error_class]
          # guid and title should be present from the RSS entry
          assert error_entry.key?(:guid)
          assert error_entry.key?(:title)
        ensure
          singleton.alias_method :call, :call_without_stub
          singleton.remove_method :call_without_stub
        end
      end

      test "normalize_item_error handles entry without guid or title gracefully" do
        url = "https://example.com/error-no-guid.xml"
        source = build_source(name: "Error No Guid", feed_url: url)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        # Create a minimal entry-like object without guid/title methods
        error_message = "item creation failed"
        singleton = SourceMonitor::Items::ItemCreator.singleton_class
        singleton.alias_method :call_without_stub, :call
        call_count = 0
        singleton.define_method(:call) do |source:, entry:|
          call_count += 1
          raise StandardError, error_message
        end

        begin
          result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

          assert_equal :fetched, result.status
          assert result.item_processing.failed.positive?
          error_entry = result.item_processing.errors.first
          assert_equal error_message, error_entry[:error_message]
          assert_equal "StandardError", error_entry[:error_class]
        ensure
          singleton.alias_method :call, :call_without_stub
          singleton.remove_method :call_without_stub
        end
      end

      test "process_feed_entries tracks created and updated items separately" do
        url = "https://example.com/create-update-items.xml"
        source = build_source(name: "Create Update", feed_url: url)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        # First fetch: all items should be created
        result1 = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        assert_equal :fetched, result1.status
        assert result1.item_processing.created.positive?
        assert_equal 0, result1.item_processing.updated
        assert_equal result1.item_processing.created, result1.item_processing.created_items.size
        assert_empty result1.item_processing.updated_items

        # Second fetch with same content: items should be updated, not created
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        result2 = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        assert_equal :fetched, result2.status
        assert_equal 0, result2.item_processing.created
        assert result2.item_processing.updated.positive?
        assert_empty result2.item_processing.created_items
        assert_equal result2.item_processing.updated, result2.item_processing.updated_items.size
      end

      test "failure result includes empty EntryProcessingResult" do
        url = "https://example.com/failure-processing.xml"
        source = build_source(name: "Failure Processing", feed_url: url)

        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("boom"))

        result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

        assert_equal :failed, result.status
        refute_nil result.item_processing
        assert_equal 0, result.item_processing.created
        assert_equal 0, result.item_processing.updated
        assert_equal 0, result.item_processing.failed
        assert_empty result.item_processing.items
        assert_empty result.item_processing.errors
        assert_empty result.item_processing.created_items
        assert_empty result.item_processing.updated_items
      end

      # ── Task 5: Jitter, interval helpers, and metadata management ──

      test "jitter_offset returns zero for zero or negative interval" do
        url = "https://example.com/jitter-zero.xml"
        source = build_source(name: "Jitter Zero", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_equal 0, fetcher.send(:jitter_offset, 0)
        assert_equal 0, fetcher.send(:jitter_offset, -10)
      end

      test "jitter_offset uses jitter_proc when provided" do
        url = "https://example.com/jitter-proc.xml"
        source = build_source(name: "Jitter Proc", feed_url: url)

        custom_jitter = ->(interval) { interval * 0.5 }
        fetcher = FeedFetcher.new(source: source, jitter: custom_jitter)

        assert_equal 50.0, fetcher.send(:jitter_offset, 100)
        assert_equal 0.0, fetcher.send(:jitter_offset, 0)
      end

      test "adjusted_interval_with_jitter never goes below min_fetch_interval" do
        url = "https://example.com/jitter-min.xml"
        source = build_source(name: "Jitter Min", feed_url: url)

        # Use a jitter proc that always returns a large negative number
        negative_jitter = ->(_) { -999_999 }
        fetcher = FeedFetcher.new(source: source, jitter: negative_jitter)

        min = FeedFetcher::MIN_FETCH_INTERVAL
        result = fetcher.send(:adjusted_interval_with_jitter, min)
        assert result >= min
      end

      test "body_digest returns nil for blank body" do
        url = "https://example.com/digest-blank.xml"
        source = build_source(name: "Digest Blank", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_nil fetcher.send(:body_digest, nil)
        assert_nil fetcher.send(:body_digest, "")
      end

      test "body_digest returns SHA256 hex for non-blank body" do
        url = "https://example.com/digest-body.xml"
        source = build_source(name: "Digest Body", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        body = "test content"
        expected = Digest::SHA256.hexdigest(body)
        assert_equal expected, fetcher.send(:body_digest, body)
      end

      test "updated_metadata removes dynamic_fetch_interval_seconds key" do
        url = "https://example.com/metadata-cleanup.xml"
        source = build_source(name: "Metadata Cleanup", feed_url: url)
        source.update!(metadata: { "dynamic_fetch_interval_seconds" => 3600, "other_key" => "keep" })

        fetcher = FeedFetcher.new(source: source)
        result = fetcher.send(:updated_metadata)

        refute result.key?("dynamic_fetch_interval_seconds")
        assert_equal "keep", result["other_key"]
      end

      test "updated_metadata stores feed_signature when provided" do
        url = "https://example.com/metadata-sig.xml"
        source = build_source(name: "Metadata Sig", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        result = fetcher.send(:updated_metadata, feed_signature: "abc123")

        assert_equal "abc123", result["last_feed_signature"]
      end

      test "updated_metadata does not set last_feed_signature when nil" do
        url = "https://example.com/metadata-no-sig.xml"
        source = build_source(name: "Metadata No Sig", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        result = fetcher.send(:updated_metadata, feed_signature: nil)

        refute result.key?("last_feed_signature")
      end

      test "feed_signature_changed? returns false when signature is blank" do
        url = "https://example.com/sig-blank.xml"
        source = build_source(name: "Sig Blank", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        refute fetcher.send(:feed_signature_changed?, nil)
        refute fetcher.send(:feed_signature_changed?, "")
      end

      test "feed_signature_changed? returns true when signature differs from stored" do
        url = "https://example.com/sig-changed.xml"
        source = build_source(name: "Sig Changed", feed_url: url)
        source.update!(metadata: { "last_feed_signature" => "old_sig" })

        fetcher = FeedFetcher.new(source: source)
        assert fetcher.send(:feed_signature_changed?, "new_sig")
      end

      test "feed_signature_changed? returns false when signature matches stored" do
        url = "https://example.com/sig-same.xml"
        source = build_source(name: "Sig Same", feed_url: url)
        source.update!(metadata: { "last_feed_signature" => "same_sig" })

        fetcher = FeedFetcher.new(source: source)
        refute fetcher.send(:feed_signature_changed?, "same_sig")
      end

      test "configured_seconds returns default when minutes_value is nil" do
        url = "https://example.com/config-nil.xml"
        source = build_source(name: "Config Nil", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        result = fetcher.send(:configured_seconds, nil, 999)
        assert_equal 999, result
      end

      test "configured_seconds returns default when minutes_value is zero" do
        url = "https://example.com/config-zero.xml"
        source = build_source(name: "Config Zero", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        result = fetcher.send(:configured_seconds, 0, 999)
        assert_equal 999, result
      end

      test "configured_seconds converts positive minutes to seconds" do
        url = "https://example.com/config-positive.xml"
        source = build_source(name: "Config Positive", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        result = fetcher.send(:configured_seconds, 10, 999)
        assert_equal 600.0, result
      end

      test "configured_positive returns default for nil" do
        url = "https://example.com/config-pos-nil.xml"
        source = build_source(name: "Config Pos Nil", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_equal 42, fetcher.send(:configured_positive, nil, 42)
      end

      test "configured_positive returns default for zero" do
        url = "https://example.com/config-pos-zero.xml"
        source = build_source(name: "Config Pos Zero", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_equal 42, fetcher.send(:configured_positive, 0, 42)
      end

      test "configured_positive returns value when positive" do
        url = "https://example.com/config-pos-val.xml"
        source = build_source(name: "Config Pos Val", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_equal 7.5, fetcher.send(:configured_positive, 7.5, 42)
      end

      test "configured_non_negative returns zero for nil since nil.to_f is 0.0" do
        url = "https://example.com/config-nn-nil.xml"
        source = build_source(name: "Config NN Nil", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        # nil.respond_to?(:to_f) is true, nil.to_f => 0.0, which is non-negative
        assert_equal 0.0, fetcher.send(:configured_non_negative, nil, 0.1)
      end

      test "configured_non_negative returns zero for negative value" do
        url = "https://example.com/config-nn-neg.xml"
        source = build_source(name: "Config NN Neg", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_equal 0.0, fetcher.send(:configured_non_negative, -5, 0.1)
      end

      # ── Task 6: SSL cert store regression test ──

      test "fetches Netflix Tech Blog feed via Medium RSS" do
        source = build_source(
          name: "Netflix Tech Blog",
          feed_url: "https://netflixtechblog.com/feed"
        )

        result = nil
        VCR.use_cassette("source_monitor/fetching/netflix_medium_rss") do
          result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        end

        assert_equal :fetched, result.status
        assert_not_nil result.feed
        assert_kind_of Feedjira::Parser::RSS, result.feed
        assert result.feed.entries.any?, "Expected at least one feed entry"
        assert_match(/netflix/i, result.feed.title.to_s)
      end

      test "configured_non_negative returns zero for zero value" do
        url = "https://example.com/config-nn-zero.xml"
        source = build_source(name: "Config NN Zero", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_equal 0, fetcher.send(:configured_non_negative, 0, 0.1)
      end

      test "interval_minutes_for returns minimum of 1" do
        url = "https://example.com/interval-min.xml"
        source = build_source(name: "Interval Min", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_equal 1, fetcher.send(:interval_minutes_for, 10)
        assert_equal 1, fetcher.send(:interval_minutes_for, 30)
        assert_equal 5, fetcher.send(:interval_minutes_for, 300)
      end

      test "parse_http_time returns nil for blank value" do
        url = "https://example.com/parse-blank.xml"
        source = build_source(name: "Parse Blank", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_nil fetcher.send(:parse_http_time, nil)
        assert_nil fetcher.send(:parse_http_time, "")
      end

      test "parse_http_time returns nil for invalid date" do
        url = "https://example.com/parse-invalid.xml"
        source = build_source(name: "Parse Invalid", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_nil fetcher.send(:parse_http_time, "not-a-date")
      end

      test "parse_http_time parses valid httpdate" do
        url = "https://example.com/parse-valid.xml"
        source = build_source(name: "Parse Valid", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        time = Time.utc(2024, 3, 15, 10, 30, 0)
        result = fetcher.send(:parse_http_time, time.httpdate)
        assert_equal time, result
      end

      test "extract_numeric returns numeric values directly" do
        url = "https://example.com/extract-num.xml"
        source = build_source(name: "Extract Num", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        assert_equal 42, fetcher.send(:extract_numeric, 42)
        assert_equal 3.14, fetcher.send(:extract_numeric, 3.14)
      end

      test "extract_numeric returns 0.0 for nil since nil.respond_to?(:to_f) is true" do
        url = "https://example.com/extract-nil.xml"
        source = build_source(name: "Extract Nil", feed_url: url)

        fetcher = FeedFetcher.new(source: source)
        # nil.respond_to?(:to_f) => true, nil.to_f => 0.0
        assert_equal 0.0, fetcher.send(:extract_numeric, nil)
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
