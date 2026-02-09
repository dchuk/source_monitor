# frozen_string_literal: true

require "test_helper"
require "digest"
require "securerandom"

module SourceMonitor
  module Items
    class ItemCreatorTest < ActiveSupport::TestCase
      setup do
        SourceMonitor::Item.delete_all
        SourceMonitor::Source.delete_all
        @source = build_source
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
        source = build_source(feed_content_readability_enabled: true)
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
        source = build_source(feed_content_readability_enabled: false)
        entry = parse_entry("feeds/rss_readability_content.xml")

        result = ItemCreator.call(source: source, entry: entry)
        assert result.created?

        item = result.item
        assert_includes item.content, "The first paragraph", "expected raw feed content to remain"
        assert_nil item.metadata["feed_content_processing"], "expected no processing metadata when readability disabled"
      end

      test "extracts extended metadata from rss entry" do
        entry = parse_entry("feeds/rss_metadata_sample.xml")

        result = ItemCreator.call(source: @source, entry:)
        assert result.created?
        item = result.item

        assert_equal "John Creator", item.author
        assert_equal [ "jane@example.com (Jane Author)", "John Creator" ], item.authors
        assert_equal [ "Technology", "Ruby" ], item.categories
        assert_equal [ "Technology", "Ruby" ], item.tags
        assert_equal [ "feed monitoring", "rss" ], item.keywords
        assert_equal "https://example.com/assets/thumb.jpg", item.media_thumbnail_url
        assert_equal(
          [
            {
              "url" => "https://example.com/assets/audio.mp3",
              "type" => "audio/mpeg",
              "length" => 67_890,
              "source" => "rss_enclosure"
            }
          ],
          item.enclosures
        )
        assert_equal(
          [
            {
              "url" => "https://example.com/assets/video.mp4",
              "type" => "video/mp4",
              "file_size" => 12_345
            }
          ],
          item.media_content
        )
        assert_equal "https://example.com/posts/1", item.comments_url
        assert_equal 12, item.comments_count
        assert_equal "Rich Hello World", item.title
        assert_equal "<p>First item content.</p>", item.content
        assert_equal "First item content.", item.summary

        metadata = item.metadata.fetch("feedjira_entry")
        assert_equal "Rich Hello World", metadata["title"]
        assert_equal "https://example.com/posts/1", metadata["url"]
      end

      test "captures json feed authors tags and attachments" do
        entry = parse_entry("feeds/json_feed_sample.json")

        result = ItemCreator.call(source: @source, entry:)
        assert result.created?
        item = result.item

        assert_equal "JSON Primary Author", item.author
        assert_equal [ "JSON Primary Author", "JSON Secondary Author" ], item.authors
        assert_equal [ "JSON", "Feeds" ], item.categories
        assert_equal [ "JSON", "Feeds" ], item.tags
        assert_equal(
          [
            {
              "url" => "https://example.com/media/podcast.mp3",
              "type" => "audio/mpeg",
              "length" => 123_456,
              "duration" => 3_600,
              "title" => "Podcast Episode 1",
              "source" => "json_feed_attachment"
            }
          ],
          item.enclosures
        )
        assert_nil item.media_thumbnail_url
        assert_equal [], item.media_content
        assert_equal "en-US", item.language
        assert_equal "Copyright 2025 Example", item.copyright
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

        assert duplicate_result.updated?
        duplicate_item = duplicate_result.item

        assert_equal 1, SourceMonitor::Item.count
        assert_equal created_item.id, duplicate_item.id
        assert_equal created_item.guid, duplicate_item.guid

        assert_equal 1, duplicate_events.size
        payload = duplicate_events.first
        assert_equal :fingerprint, payload[:matched_by]
        assert_equal created_item.content_fingerprint, payload[:content_fingerprint]
      end

      private

      def build_source(attributes = {})
        defaults = {
          name: "Example Source",
          feed_url: "https://example.com/feed-#{SecureRandom.hex(8)}.xml",
          website_url: "https://example.com",
          fetch_interval_minutes: 60
        }

        create_source!(defaults.merge(attributes))
      end

      def parse_entry(fixture)
        data = File.read(file_fixture(fixture))
        Feedjira.parse(data).entries.first
      end
    end
  end
end
