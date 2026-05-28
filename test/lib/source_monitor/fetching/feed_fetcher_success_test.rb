# frozen_string_literal: true

require "test_helper"
require "faraday"
require "uri"
require "digest"
require "ostruct"
require_relative "feed_fetcher_test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcherSuccessTest < ActiveSupport::TestCase
      include FeedFetcherTestHelper

      test "success outcome owns source log instrumentation and result values" do
        travel_to Time.zone.parse("2024-06-01 12:00:00 UTC")

        source = build_source(name: "Success Outcome", feed_url: "https://example.com/outcome.xml")
        adaptive_interval = FeedFetcher::AdaptiveInterval.new(source: source, jitter_proc: ->(_) { 0 })
        source_updater = FeedFetcher::SourceUpdater.new(source: source, adaptive_interval: adaptive_interval)
        response = FeedFetcher::ResponseWrapper.new(
          status: 200,
          headers: { "ETag" => '"success-outcome"' },
          body: "<rss>body</rss>"
        )
        feed = OpenStruct.new(entries: [ OpenStruct.new(entry_id: "entry-1") ])
        item_processing = FeedFetcher::EntryProcessingResult.new(
          created: 2,
          updated: 1,
          unchanged: 0,
          failed: 1,
          items: [],
          errors: [ { guid: "bad", error_message: "failed" } ],
          created_items: [],
          updated_items: []
        )
        instrumentation_payload = {}

        result = FeedFetcher::SuccessOutcome.new(
          response: response,
          body: response.body,
          feed: feed,
          item_processing: item_processing,
          feed_signature: "feed-signature",
          content_changed: true,
          entries_digest: "entries-digest"
        ).apply(source_updater: source_updater, started_at: Time.current, instrumentation_payload: instrumentation_payload)

        assert_equal :fetched, result.status
        assert_equal feed, result.feed
        assert_equal item_processing, result.item_processing

        source.reload
        assert_equal 200, source.last_http_status
        assert_equal '"success-outcome"', source.etag
        assert_equal "feed-signature", source.metadata["last_feed_signature"]
        assert_equal "entries-digest", source.metadata["last_entries_digest"]

        log = source.fetch_logs.order(:created_at).last
        assert log.success
        assert_equal 2, log.items_created
        assert_equal 1, log.items_updated
        assert_equal 1, log.items_failed
        assert_equal "feed-signature", log.metadata["feed_signature"]
        assert_equal "failed", log.metadata["item_errors"].first["error_message"]

        assert_equal true, instrumentation_payload[:success]
        assert_equal :fetched, instrumentation_payload[:status]
        assert_equal 200, instrumentation_payload[:http_status]
        assert_equal OpenStruct.name, instrumentation_payload[:parser]
        assert_equal 2, instrumentation_payload[:items_created]
        assert_equal 1, instrumentation_payload[:items_updated]
        assert_equal 1, instrumentation_payload[:items_failed]
        assert_equal 0, instrumentation_payload[:retry_attempt]
      ensure
        travel_back
      end

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
        singleton.define_method(:call) do |source:, entry:, **kwargs|
          call_count += 1
          if call_count == 1
            raise StandardError, error_message
          else
            call_without_stub(source:, entry:, **kwargs)
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
    end
  end
end
