# frozen_string_literal: true

require "test_helper"
require "faraday"
require "uri"
require "digest"
require_relative "feed_fetcher_test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcherErrorHandlingTest < ActiveSupport::TestCase
      include FeedFetcherTestHelper

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

      # -- AIA Certificate Resolution --

      test "retries with AIA resolution when SSLError occurs and intermediate found" do
        url = "https://example.com/aia-success.xml"
        source = build_source(name: "AIA Success", feed_url: url)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        call_count = 0
        stub_request(:get, url).to_return { |_req|
          call_count += 1
          if call_count == 1
            raise Faraday::SSLError, "certificate verify failed"
          else
            { status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" } }
          end
        }

        SourceMonitor::HTTP::AIAResolver.stub(:resolve, :mock_cert) do
          SourceMonitor::HTTP::AIAResolver.stub(:enhanced_cert_store, OpenSSL::X509::Store.new) do
            result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
            assert_equal :fetched, result.status
          end
        end
      end

      test "raises ConnectionError when SSLError occurs and AIA resolve returns nil" do
        url = "https://example.com/aia-nil.xml"
        source = build_source(name: "AIA Nil", feed_url: url)

        stub_request(:get, url).to_raise(Faraday::SSLError.new("certificate verify failed"))

        SourceMonitor::HTTP::AIAResolver.stub(:resolve, nil) do
          result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
          assert_equal :failed, result.status
          assert_kind_of SourceMonitor::Fetching::ConnectionError, result.error
        end
      end

      test "does not attempt AIA resolution for non-SSL ConnectionFailed" do
        url = "https://example.com/aia-not-attempted.xml"
        source = build_source(name: "AIA Not Attempted", feed_url: url)

        stub_request(:get, url).to_raise(Faraday::ConnectionFailed.new("connection refused"))

        resolve_called = false
        mock_resolve = ->(_hostname, **_opts) { resolve_called = true; nil }
        SourceMonitor::HTTP::AIAResolver.stub(:resolve, mock_resolve) do
          result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
          assert_equal :failed, result.status
          assert_kind_of SourceMonitor::Fetching::ConnectionError, result.error
          refute resolve_called, "AIAResolver.resolve should not be called for ConnectionFailed"
        end
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
    end
  end
end
