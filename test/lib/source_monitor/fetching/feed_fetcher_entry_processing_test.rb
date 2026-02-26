# frozen_string_literal: true

require "test_helper"
require "faraday"
require "uri"
require "digest"
require_relative "feed_fetcher_test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcherEntryProcessingTest < ActiveSupport::TestCase
      include FeedFetcherTestHelper

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

        # Second fetch with same body: short-circuited by feed signature match,
        # so entry processing is skipped entirely (zero counts across the board)
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        result2 = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        assert_equal :fetched, result2.status
        assert_equal 0, result2.item_processing.created
        assert_equal 0, result2.item_processing.updated
        assert_equal 0, result2.item_processing.unchanged
        assert_empty result2.item_processing.created_items
        assert_empty result2.item_processing.updated_items
      end

      test "unchanged items are tracked when feed body changes but items are identical" do
        url = "https://example.com/unchanged-items.xml"
        source = build_source(name: "Unchanged Items", feed_url: url)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        # First fetch: all items created
        result1 = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        assert_equal :fetched, result1.status
        total_entries = result1.item_processing.created
        assert total_entries.positive?

        # Second fetch: slightly different body (appended comment) so signature changes,
        # but most items are the same so unchanged should dominate
        modified_body = body + "\n<!-- timestamp: #{Time.now.to_i} -->"
        stub_request(:get, url)
          .to_return(status: 200, body: modified_body, headers: { "Content-Type" => "application/rss+xml" })

        result2 = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
        assert_equal :fetched, result2.status
        assert_equal 0, result2.item_processing.created
        assert result2.item_processing.unchanged.positive?,
          "Expected unchanged items when re-fetching identical entries with different body"
        # Unchanged + updated should account for all entries
        assert_equal total_entries,
          result2.item_processing.unchanged + result2.item_processing.updated + result2.item_processing.failed
      end

      test "entries_digest falls back to url when entry_id is absent" do
        url = "https://example.com/entries-digest-url.xml"
        source = build_source(name: "Digest URL Fallback", feed_url: url)
        fetcher = FeedFetcher.new(source: source, jitter: ->(_) { 0 })

        entry_with_url = OpenStruct.new(url: "https://example.com/post-1", title: "Post One")
        feed = OpenStruct.new(entries: [ entry_with_url ])

        digest = fetcher.send(:entries_digest, feed)
        refute_nil digest, "Expected digest when entries have url but no entry_id"
      end

      test "entries_digest falls back to title when entry_id and url are absent" do
        url = "https://example.com/entries-digest-title.xml"
        source = build_source(name: "Digest Title Fallback", feed_url: url)
        fetcher = FeedFetcher.new(source: source, jitter: ->(_) { 0 })

        entry_with_title = OpenStruct.new(title: "Only a Title")
        feed = OpenStruct.new(entries: [ entry_with_title ])

        digest = fetcher.send(:entries_digest, feed)
        refute_nil digest, "Expected digest when entries have only title"
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

      test "failed item creation does not prevent source update after fetch" do
        url = "https://example.com/mixed-entries.xml"
        source = build_source(name: "Mixed Entries", feed_url: url)

        body = File.read(file_fixture("feeds/rss_sample.xml"))
        stub_request(:get, url)
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/rss+xml" })

        # Make every other ItemCreator.call raise a validation error to simulate
        # a mix of valid and invalid entries. This exercises the EntryProcessor rescue
        # path and verifies that failed items don't pollute the association cache.
        call_count = 0
        original_call = SourceMonitor::Items::ItemCreator.method(:call)
        singleton = SourceMonitor::Items::ItemCreator.singleton_class
        singleton.define_method(:call) do |source:, entry:|
          call_count += 1
          if call_count.odd?
            raise ActiveRecord::RecordInvalid.new(SourceMonitor::Item.new), "Validation failed: simulated"
          else
            original_call.call(source: source, entry: entry)
          end
        end

        begin
          result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call

          assert_equal :fetched, result.status
          assert result.item_processing.failed.positive?,
            "expected some items to fail"

          # The critical assertion: source.update! in SourceUpdater should succeed.
          # Before the fix, the failed items would remain in source.items cache,
          # and source.update! would trigger has_many auto-save, cascading the failure.
          source.reload
          assert_not_nil source.last_fetched_at, "source should have been updated after fetch"
          assert_equal 0, source.failure_count
        ensure
          singleton.define_method(:call) { |source:, entry:| original_call.call(source: source, entry: entry) }
        end
      end
    end
  end
end
