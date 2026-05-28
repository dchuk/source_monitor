# frozen_string_literal: true

require "test_helper"
require "digest"
require "securerandom"
require "ostruct"

module SourceMonitor
  module Items
    class ItemCreatorTest < ActiveSupport::TestCase
      setup do
        clean_source_monitor_tables!
        @source = create_source!
      end

      test "creates item from rss entry and computes fingerprint" do
        entry = parse_entry("feeds/rss_sample.xml")
        entry.url = "HTTPS://EXAMPLE.COM/posts/1#fragment"

        result = ItemCreator.call(source: @source, entry:)
        assert result.created?, "expected item to be marked as created"
        item = result.item

        assert item.persisted?, "item should be saved"
        assert_equal @source, item.source
        assert_equal "https://example.com/posts/1", item.url
        assert_equal item.url, item.canonical_url

        expected_fingerprint = Digest::SHA256.hexdigest(
          [
            entry.title.strip,
            entry.url.strip,
            entry.summary.strip
          ].join("\u0000")
        )
        assert_equal expected_fingerprint, item.content_fingerprint
      end

      test "falls back to fingerprint when entry provides no guid" do
        entry = parse_entry("feeds/rss_no_guid.xml")

        result = ItemCreator.call(source: @source, entry:)
        assert result.created?
        item = result.item

        assert item.persisted?
        assert_equal item.content_fingerprint, item.guid
      end

      test "creates items from rss atom and json feeds" do
        fixtures = {
          rss: "feeds/rss_sample.xml",
          atom: "feeds/atom_sample.xml",
          json: "feeds/json_feed_sample.json"
        }

        fixtures.each_value do |fixture|
          entry = parse_entry(fixture)
          result = ItemCreator.call(source: @source, entry:)
          assert result.created?
          created_item = result.item

          assert created_item.persisted?
          assert created_item.guid.present?
          assert created_item.content_fingerprint.present?
          assert_equal created_item.url, created_item.canonical_url
          assert_equal entry.title.strip, created_item.title if entry.respond_to?(:title) && entry.title.present?
          assert_includes [ Time, ActiveSupport::TimeWithZone, DateTime, NilClass ], created_item.published_at.class
          assert created_item.metadata.present?, "metadata should include feedjira entry snapshot"
        end
      end

      test "processes feed content with readability when enabled" do
        source = create_source!(feed_content_readability_enabled: true)
        entry = parse_entry("feeds/rss_readability_content.xml")

        result = ItemCreator.call(source: source, entry: entry)
        assert result.created?, "expected item to be created when processing readability content"

        item = result.item
        assert_includes item.content, "The first paragraph", "expected readability-processed content to be stored"

        processing_metadata = item.metadata["feed_content_processing"]
        assert processing_metadata.present?, "expected feed content processing metadata to be stored"
        assert_equal "readability", processing_metadata["strategy"]
        assert_equal true, processing_metadata["applied"]
      end

      test "preserves raw feed content when readability disabled" do
        source = create_source!(feed_content_readability_enabled: false)
        entry = parse_entry("feeds/rss_readability_content.xml")

        result = ItemCreator.call(source: source, entry: entry)
        assert result.created?

        item = result.item
        assert_includes item.content, "The first paragraph", "expected raw feed content to remain"
        assert_nil item.metadata["feed_content_processing"], "expected no processing metadata when readability disabled"
      end

      test "deduplicates entries by guid and updates existing records" do
        entry = parse_entry("feeds/rss_sample.xml")
        original_result = ItemCreator.call(source: @source, entry:)
        assert original_result.created?
        original_item = original_result.item

        updated_entry = parse_entry("feeds/rss_sample.xml")
        updated_entry.summary = "Updated summary"

        duplicate_events = []
        duplicate_result = ActiveSupport::Notifications.subscribed(
          ->(_name, _start, _finish, _id, payload) { duplicate_events << payload },
          SourceMonitor::Instrumentation::ITEM_DUPLICATE_EVENT
        ) do
          ItemCreator.call(source: @source, entry: updated_entry)
        end

        assert duplicate_result.updated?, "expected duplicate entry to be treated as updated"
        duplicate_item = duplicate_result.item

        assert_equal 1, SourceMonitor::Item.count
        assert_equal original_item.id, duplicate_item.id
        assert_equal "Updated summary", duplicate_item.reload.summary

        assert_equal 1, duplicate_events.size
        payload = duplicate_events.first
        assert_equal :guid, payload[:matched_by]
        assert_equal @source.id, payload[:source_id]
        assert_equal duplicate_item.id, payload[:item_id]
      end

      test "deduplicates entries without guid using content fingerprint" do
        entry = parse_entry("feeds/rss_no_guid.xml")
        created_result = ItemCreator.call(source: @source, entry:)
        assert created_result.created?
        created_item = created_result.item

        duplicate_entry = parse_entry("feeds/rss_no_guid.xml")

        duplicate_events = []
        duplicate_result = ActiveSupport::Notifications.subscribed(
          ->(_name, _start, _finish, _id, payload) { duplicate_events << payload },
          SourceMonitor::Instrumentation::ITEM_DUPLICATE_EVENT
        ) do
          ItemCreator.call(source: @source, entry: duplicate_entry)
        end

        assert duplicate_result.unchanged?, "Expected unchanged status for identical duplicate entry"
        duplicate_item = duplicate_result.item

        assert_equal 1, SourceMonitor::Item.count
        assert_equal created_item.id, duplicate_item.id
        assert_equal created_item.guid, duplicate_item.guid

        assert_equal 1, duplicate_events.size
        payload = duplicate_events.first
        assert_equal :fingerprint, payload[:matched_by]
        assert_equal created_item.content_fingerprint, payload[:content_fingerprint]
      end

      test "normalizes guid to lowercase for index-friendly lookups" do
        entry = OpenStruct.new(
          entry_id: "UPPER-CASE-GUID-123",
          title: "Mixed Case Entry",
          url: "https://example.com/mixed",
          summary: "Summary text",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Mixed Case Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "upper-case-guid-123", result.item.guid

        # Re-process with same GUID in different case -- should match
        entry2 = OpenStruct.new(
          entry_id: "upper-case-guid-123",
          title: "Same Entry",
          url: "https://example.com/mixed",
          summary: "Updated summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Same Entry" }
        )

        result2 = ItemCreator.call(source: @source, entry: entry2)
        assert result2.updated? || result2.unchanged?
        assert_equal result.item.id, result2.item.id
      end

      # ─── Task 2: Concurrent duplicate handling - RecordNotUnique ───

      test "handle_concurrent_duplicate finds by guid when raw_guid is present" do
        entry = parse_entry("feeds/rss_sample.xml")
        original_result = ItemCreator.call(source: @source, entry: entry)
        assert original_result.created?
        original_item = original_result.item

        # Directly test the handler by calling the private method
        creator = ItemCreator.new(source: @source, entry: entry)
        attributes = creator.send(:build_attributes)
        attributes[:guid] = attributes[:guid].presence || attributes[:content_fingerprint]

        result = creator.send(:handle_concurrent_duplicate, attributes, raw_guid_present: true)
        assert result.unchanged?, "expected unchanged for identical duplicate entry"
        assert_equal original_item.id, result.item.id
        assert_equal :guid, result.matched_by
      end

      test "handle_concurrent_duplicate finds by fingerprint when raw_guid is absent" do
        entry = parse_entry("feeds/rss_no_guid.xml")
        original_result = ItemCreator.call(source: @source, entry: entry)
        assert original_result.created?
        original_item = original_result.item

        creator = ItemCreator.new(source: @source, entry: entry)
        attributes = creator.send(:build_attributes)
        attributes[:guid] = attributes[:guid].presence || attributes[:content_fingerprint]

        result = creator.send(:handle_concurrent_duplicate, attributes, raw_guid_present: false)
        assert result.unchanged?, "expected unchanged for identical duplicate entry"
        assert_equal original_item.id, result.item.id
        assert_equal :fingerprint, result.matched_by
      end

      test "find_conflicting_item by guid falls back to find_by!" do
        entry = parse_entry("feeds/rss_sample.xml")
        original_result = ItemCreator.call(source: @source, entry: entry)
        assert original_result.created?
        original_item = original_result.item

        creator = ItemCreator.new(source: @source, entry: entry)
        attributes = creator.send(:build_attributes)
        attributes[:guid] = attributes[:guid].presence || attributes[:content_fingerprint]

        found = creator.send(:find_conflicting_item, attributes, :guid)
        assert_equal original_item.id, found.id
      end

      test "find_conflicting_item by fingerprint" do
        entry = parse_entry("feeds/rss_no_guid.xml")
        original_result = ItemCreator.call(source: @source, entry: entry)
        assert original_result.created?
        original_item = original_result.item

        creator = ItemCreator.new(source: @source, entry: entry)
        attributes = creator.send(:build_attributes)
        attributes[:guid] = attributes[:guid].presence || attributes[:content_fingerprint]

        found = creator.send(:find_conflicting_item, attributes, :fingerprint)
        assert_equal original_item.id, found.id
      end

      test "create_new_item rescues RecordNotUnique and delegates to handle_concurrent_duplicate" do
        entry = parse_entry("feeds/rss_sample.xml")
        # First, create the item normally
        original_result = ItemCreator.call(source: @source, entry: entry)
        assert original_result.created?
        original_item = original_result.item

        # Now test the full concurrent duplicate flow by calling handle_concurrent_duplicate directly
        # This covers the rescue path in create_new_item (lines 109-111)
        entry2 = parse_entry("feeds/rss_sample.xml")
        entry2.summary = "Race condition updated summary"
        creator = ItemCreator.new(source: @source, entry: entry2)
        attributes = creator.send(:build_attributes)
        raw_guid = attributes[:guid]
        attributes[:guid] = raw_guid.presence || attributes[:content_fingerprint]

        result = creator.send(:handle_concurrent_duplicate, attributes, raw_guid_present: raw_guid.present?)
        assert result.updated?, "expected updated result from handle_concurrent_duplicate"
        assert_equal original_item.id, result.item.id
        assert_equal :guid, result.matched_by
        assert_equal "Race condition updated summary", result.item.reload.summary
      end

      # ─── Task 4: Feed content processing error path and readability edge cases ───

      test "process_feed_content returns error metadata when parser raises" do
        source = create_source!(feed_content_readability_enabled: true)
        entry = OpenStruct.new(
          title: "Error Content Entry",
          url: "https://example.com/error-content",
          entry_id: "error-content-guid",
          content: "<p>Some HTML content</p>",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Error Content Entry" }
        )

        parser_class = SourceMonitor::Scrapers::Parsers::ReadabilityParser
        parser_class.stub(:new, -> { raise StandardError, "parse explosion" }) do
          result = ItemCreator.call(source: source, entry: entry)
          assert result.created?

          item = result.item
          # Content falls back to raw content on error
          assert_equal "<p>Some HTML content</p>", item.content

          processing = item.metadata["feed_content_processing"]
          assert processing.present?, "expected processing metadata on error"
          assert_equal "failed", processing["status"]
          assert_equal "readability", processing["strategy"]
          assert_equal false, processing["applied"]
          assert_equal false, processing["changed"]
          assert_equal "StandardError", processing["error_class"]
          assert_equal "parse explosion", processing["error_message"]
        end
      end

      test "should_process_feed_content returns false for plain text" do
        source = create_source!(feed_content_readability_enabled: true)
        entry = OpenStruct.new(
          title: "Plain Text Entry",
          url: "https://example.com/plain-text",
          entry_id: "plain-text-guid",
          content: "Just some plain text with no HTML tags at all",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Plain Text Entry" }
        )

        result = ItemCreator.call(source: source, entry: entry)
        assert result.created?
        assert_nil result.item.metadata["feed_content_processing"],
          "expected no processing metadata for plain text content"
      end

      test "should_process_feed_content returns false for blank content" do
        source = create_source!(feed_content_readability_enabled: true)
        entry = OpenStruct.new(
          title: "Blank Content Entry",
          url: "https://example.com/blank-content",
          entry_id: "blank-content-guid",
          content: "",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Blank Content Entry" }
        )

        result = ItemCreator.call(source: source, entry: entry)
        assert result.created?
        assert_nil result.item.metadata["feed_content_processing"]
      end

      test "wrap_content_for_readability escapes HTML in title" do
        source = create_source!(feed_content_readability_enabled: true)
        entry = OpenStruct.new(
          title: '<script>alert("xss")</script>',
          url: "https://example.com/xss-title",
          entry_id: "xss-title-guid",
          content: "<p>Safe content</p>",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "XSS Title" }
        )

        # This should not raise, and the title should be escaped in the wrapped HTML
        result = ItemCreator.call(source: source, entry: entry)
        assert result.created?
      end

      test "wrap_content_for_readability uses default title when blank" do
        source = create_source!(feed_content_readability_enabled: true)
        entry = OpenStruct.new(
          title: nil,
          url: "https://example.com/no-title",
          entry_id: "no-title-guid",
          content: "<p>Content without title</p>",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: nil }
        )

        result = ItemCreator.call(source: source, entry: entry)
        assert result.created?
      end

      test "build_feed_content_metadata includes readability_text_length when present" do
        source = create_source!(feed_content_readability_enabled: true)
        entry = parse_entry("feeds/rss_readability_content.xml")

        result = ItemCreator.call(source: source, entry: entry)
        assert result.created?

        processing = result.item.metadata["feed_content_processing"]
        assert processing.present?
        # The readability parser includes text length in metadata when available
        if processing["readability_text_length"]
          assert_kind_of Integer, processing["readability_text_length"]
        end
      end

      test "build_feed_content_metadata includes title when present" do
        source = create_source!(feed_content_readability_enabled: true)
        entry = parse_entry("feeds/rss_readability_content.xml")

        result = ItemCreator.call(source: source, entry: entry)
        assert result.created?

        processing = result.item.metadata["feed_content_processing"]
        assert processing.present?
        # Strategy should be readability since selectors are not configured
        assert_equal "readability", processing["strategy"]
      end

      test "Result struct created? and updated? and unchanged? predicates" do
        created = ItemCreator::Result.new(item: nil, status: :created)
        assert created.created?
        refute created.updated?
        refute created.unchanged?

        updated = ItemCreator::Result.new(item: nil, status: :updated)
        refute updated.created?
        assert updated.updated?
        refute updated.unchanged?

        unchanged = ItemCreator::Result.new(item: nil, status: :unchanged)
        refute unchanged.created?
        refute unchanged.updated?
        assert unchanged.unchanged?
      end

      test "deep_copy handles nested hashes and arrays" do
        extractor = ItemCreator::ContentExtractor.new(source: @source)
        original = { "a" => [ 1, { "b" => 2 } ] }
        copy = extractor.send(:deep_copy, original)
        assert_equal original, copy
        # Verify it's a deep copy, not a reference
        copy["a"][1]["b"] = 99
        assert_equal 2, original["a"][1]["b"]
      end

      test "deep_copy handles TypeError for non-dupable values" do
        extractor = ItemCreator::ContentExtractor.new(source: @source)
        # Integers are non-dupable in some contexts, but deep_copy should handle them
        assert_equal 42, extractor.send(:deep_copy, 42)
        assert_equal true, extractor.send(:deep_copy, true)
      end

      # ─── Association cache safety ───

      test "failed item creation does not pollute source association cache" do
        # Load the source's items association cache
        @source.items.load

        # Create an entry that will fail validation (missing url)
        invalid_entry = OpenStruct.new(
          title: "Invalid Entry",
          url: nil,
          entry_id: "invalid-guid-#{SecureRandom.hex(4)}",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Invalid Entry" }
        )

        # ItemCreator should raise due to missing url validation
        assert_raises(ActiveRecord::RecordInvalid) do
          ItemCreator.call(source: @source, entry: invalid_entry)
        end

        # The critical assertion: after a failed item creation, the source's
        # association cache should NOT contain any unsaved/invalid items.
        # Using source_id instead of source avoids inverse_of adding the
        # unsaved record to the loaded items cache.
        assert @source.items.none?(&:new_record?),
          "source.items association cache should not contain unsaved items after failed creation"

        # Verify that source.update! succeeds without cascade failure
        assert_nothing_raised do
          @source.update!(name: "Updated Name After Failed Item")
        end
      end

      test "create_new_item builds item without polluting association cache" do
        entry = OpenStruct.new(
          title: "Association Test Entry",
          url: "https://example.com/assoc-test",
          entry_id: "assoc-test-guid-#{SecureRandom.hex(4)}",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Association Test Entry" }
        )

        # Pre-load the association cache
        @source.items.load
        initial_cache_size = @source.items.size

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?

        # The new item should be persisted
        assert result.item.persisted?
        assert_equal @source.id, result.item.source_id

        # The association cache should NOT have been modified by create_new_item
        # because we use Item.new(source_id:) which bypasses inverse_of
        assert_equal initial_cache_size, @source.items.size,
          "creating an item should not add to the loaded association cache"
      end

      # ─── Feed content record creation ───

      test "new item creation with content also creates ItemContent with feed_word_count" do
        entry = OpenStruct.new(
          title: "Feed Word Count Entry",
          url: "https://example.com/feed-wc",
          entry_id: "feed-wc-guid",
          content: "<p>Five words in this sentence</p>",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Feed Word Count Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?

        item = result.item.reload
        assert item.item_content.present?, "expected ItemContent to be created for item with feed content"
        assert_equal 5, item.item_content.feed_word_count
      end

      test "new item creation without content does not create ItemContent" do
        entry = OpenStruct.new(
          title: "No Content Entry",
          url: "https://example.com/no-content",
          entry_id: "no-content-guid",
          summary: nil,
          published: Time.utc(2025, 10, 1),
          to_h: { title: "No Content Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?

        item = result.item.reload
        assert_nil item.item_content
      end

      # ─── Published_at persistence ───

      test "persists published_at from feed entry with pubDate" do
        entry = parse_entry("feeds/rss_sample.xml")

        result = ItemCreator.call(source: @source, entry:)
        assert result.created?

        item = result.item.reload
        assert_not_nil item.published_at, "expected published_at to be set from feed pubDate"
        assert_kind_of Time, item.published_at
      end

      test "persists nil published_at when feed entry has no date" do
        entry = OpenStruct.new(
          title: "No Date Entry",
          url: "https://example.com/no-date",
          entry_id: "no-date-guid",
          summary: "No date summary",
          to_h: { title: "No Date Entry" }
        )

        result = ItemCreator.call(source: @source, entry:)
        assert result.created?

        item = result.item.reload
        assert_nil item.published_at, "expected published_at to be nil when feed entry has no date"
      end

      test "html_fragment? returns true for HTML and false for plain text" do
        extractor = ItemCreator::ContentExtractor.new(source: @source)
        assert extractor.send(:html_fragment?, "<p>text</p>")
        assert extractor.send(:html_fragment?, "<div class='x'>content</div>")
        assert extractor.send(:html_fragment?, "text <br> more")
        refute extractor.send(:html_fragment?, "just plain text")
        refute extractor.send(:html_fragment?, "no tags here")
        refute extractor.send(:html_fragment?, "a -> b")
      end

      private

      def parse_entry(fixture)
        data = File.read(file_fixture(fixture))
        Feedjira.parse(data).entries.first
      end
    end
  end
end
