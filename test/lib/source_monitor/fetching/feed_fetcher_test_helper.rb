# frozen_string_literal: true

module SourceMonitor
  module Fetching
    # Shared helpers for FeedFetcher-related tests.
    #
    # Provides factory shortcuts and reusable WebMock stub helpers so that
    # individual test files don't need to duplicate HTTP stubbing logic.
    # See test/TEST_CONVENTIONS.md for mocking and stub guidelines.
    module FeedFetcherTestHelper
      private

      # Creates a Source record with fetching-specific defaults.
      def build_source(name:, feed_url:, fetch_interval_minutes: 360, adaptive_fetching_enabled: true)
        create_source!(
          name: name,
          feed_url: feed_url,
          fetch_interval_minutes: fetch_interval_minutes,
          adaptive_fetching_enabled: adaptive_fetching_enabled
        )
      end

      # Returns the SHA-256 hex digest of the given body string.
      def body_digest(body)
        Digest::SHA256.hexdigest(body)
      end

      # ---- WebMock Stub Helpers ----

      # Stubs a successful feed request. Uses file_fixture for the response body.
      #
      #   stub_feed_request(url: source.feed_url)
      #   stub_feed_request(url: source.feed_url, fixture: "feeds/atom_sample.xml", status: 200)
      #   stub_feed_request(url: source.feed_url, headers: { "ETag" => '"abc"' })
      def stub_feed_request(url:, fixture: "feeds/rss_sample.xml", status: 200, headers: {})
        response_headers = { "Content-Type" => "application/rss+xml" }.merge(headers)
        stub_request(:get, url).to_return(
          status: status,
          body: File.read(file_fixture(fixture)),
          headers: response_headers
        )
      end

      # Stubs a feed request that times out.
      #
      #   stub_feed_timeout(url: source.feed_url)
      def stub_feed_timeout(url:)
        stub_request(:get, url).to_raise(Faraday::TimeoutError.new("execution expired"))
      end

      # Stubs a feed request that returns 404 Not Found.
      #
      #   stub_feed_not_found(url: source.feed_url)
      def stub_feed_not_found(url:)
        stub_request(:get, url).to_return(status: 404, body: "Not Found")
      end

      # Stubs a feed request that fails with a connection error.
      #
      #   stub_feed_connection_failed(url: source.feed_url)
      def stub_feed_connection_failed(url:)
        stub_request(:get, url).to_raise(Faraday::ConnectionFailed.new("connection refused"))
      end
    end
  end
end
