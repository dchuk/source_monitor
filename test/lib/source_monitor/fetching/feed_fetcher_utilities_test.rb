# frozen_string_literal: true

require "test_helper"
require "faraday"
require "uri"
require "digest"
require_relative "feed_fetcher_test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcherUtilitiesTest < ActiveSupport::TestCase
      include FeedFetcherTestHelper

      # ── Request header handling ──

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

      # ── Jitter and interval helpers ──

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

      # ── Metadata management ──

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

      # ── Feed signature ──

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

      # ── Configuration helpers ──

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

      test "configured_non_negative returns zero for nil since nil.respond_to?(:to_f) is true" do
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

      # ── HTTP time parsing ──

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

      # ── Numeric extraction ──

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
    end
  end
end
