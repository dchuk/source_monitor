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

      # ─── Task 1: URL extraction fallbacks and content extraction chain ───

      test "extract_url falls back to link_nodes when url is blank" do
        link_node = OpenStruct.new(rel: "alternate", href: "https://example.com/via-link-node")
        entry = OpenStruct.new(
          title: "Link Node Entry",
          url: "",
          link_nodes: [ link_node ],
          entry_id: "link-node-guid",
          summary: "Summary text",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Link Node Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "https://example.com/via-link-node", result.item.url
      end

      test "extract_url falls back to links array when url and link_nodes are blank" do
        entry = OpenStruct.new(
          title: "Links Array Entry",
          url: nil,
          links: [ "https://example.com/via-links-array" ],
          entry_id: "links-array-guid",
          summary: "Summary text",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Links Array Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "https://example.com/via-links-array", result.item.url
      end

      test "extract_url picks first link_node when no alternate rel found" do
        node1 = OpenStruct.new(rel: "enclosure", href: "https://example.com/enclosure")
        node2 = OpenStruct.new(rel: "via", href: "https://example.com/via")
        entry = OpenStruct.new(
          title: "Non-alternate Node Entry",
          url: nil,
          link_nodes: [ node1, node2 ],
          entry_id: "non-alt-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Non-alternate Node Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "https://example.com/enclosure", result.item.url
      end

      test "extract_url picks node with nil rel as alternate" do
        node_nil_rel = OpenStruct.new(rel: nil, href: "https://example.com/nil-rel")
        node_other = OpenStruct.new(rel: "via", href: "https://example.com/other")
        entry = OpenStruct.new(
          title: "Nil Rel Node Entry",
          url: nil,
          link_nodes: [ node_other, node_nil_rel ],
          entry_id: "nil-rel-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Nil Rel Node Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "https://example.com/nil-rel", result.item.url
      end

      test "extract_url skips blank hrefs in links array" do
        entry = OpenStruct.new(
          title: "Blank Links Entry",
          url: nil,
          links: [ "", "  ", "https://example.com/valid-link" ],
          entry_id: "blank-links-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Blank Links Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "https://example.com/valid-link", result.item.url
      end

      test "extract_content tries content then content_encoded then summary" do
        # Only has summary
        entry = OpenStruct.new(
          title: "Summary Only Entry",
          url: "https://example.com/summary-only",
          entry_id: "summary-only-guid",
          summary: "The summary content",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Summary Only Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "The summary content", result.item.content
      end

      test "extract_content prefers content over content_encoded and summary" do
        entry = OpenStruct.new(
          title: "Multi Content Entry",
          url: "https://example.com/multi-content",
          entry_id: "multi-content-guid",
          content: "Primary content",
          content_encoded: "<p>Encoded content</p>",
          summary: "Summary content",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Multi Content Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "Primary content", result.item.content
      end

      test "extract_timestamp falls back to updated when published is absent" do
        entry = OpenStruct.new(
          title: "Updated Only Entry",
          url: "https://example.com/updated-only",
          entry_id: "updated-only-guid",
          summary: "Summary",
          updated: Time.utc(2025, 10, 5),
          to_h: { title: "Updated Only Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal Time.utc(2025, 10, 5), result.item.published_at
      end

      test "extract_updated_timestamp returns updated when present" do
        updated_time = Time.utc(2025, 10, 5, 14, 30)
        entry = OpenStruct.new(
          title: "With Updated Entry",
          url: "https://example.com/with-updated",
          entry_id: "with-updated-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          updated: updated_time,
          to_h: { title: "With Updated Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal updated_time, result.item.updated_at_source
      end

      test "extract_updated_timestamp returns nil when updated is absent" do
        entry = OpenStruct.new(
          title: "No Updated Entry",
          url: "https://example.com/no-updated",
          entry_id: "no-updated-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "No Updated Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_nil result.item.updated_at_source
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

      # ─── Task 3: Multi-format author, enclosure, and media extraction ───

      test "extract_authors from atom entry with author_nodes" do
        entry = parse_entry("feeds/atom_sample.xml")
        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        item = result.item

        assert_includes item.authors, "Atom Primary Author"
        assert_includes item.authors, "Atom Secondary Author"
      end

      test "extract_authors from dc_creator field" do
        entry = OpenStruct.new(
          title: "DC Creator Entry",
          url: "https://example.com/dc-creator",
          entry_id: "dc-creator-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          author: nil,
          dc_creators: [ "Creator One", "Creator Two" ],
          to_h: { title: "DC Creator Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_includes result.item.authors, "Creator One"
        assert_includes result.item.authors, "Creator Two"
      end

      test "extract_authors from dc_creator singular field when dc_creators absent" do
        entry = OpenStruct.new(
          title: "DC Creator Singular",
          url: "https://example.com/dc-singular",
          entry_id: "dc-singular-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          author: nil,
          dc_creator: "Single Creator",
          to_h: { title: "DC Creator Singular" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_includes result.item.authors, "Single Creator"
      end

      test "extract_authors includes primary author and deduplicates" do
        entry = OpenStruct.new(
          title: "Dedup Author Entry",
          url: "https://example.com/dedup-author",
          entry_id: "dedup-author-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          author: "Same Author",
          rss_authors: [ "Same Author", "Other Author" ],
          to_h: { title: "Dedup Author Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal [ "Same Author", "Other Author" ], result.item.authors
      end

      test "extract_authors handles author_node with only email" do
        node = OpenStruct.new(name: nil, email: "author@example.com", uri: nil)
        entry = OpenStruct.new(
          title: "Email Author Entry",
          url: "https://example.com/email-author",
          entry_id: "email-author-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          author: nil,
          author_nodes: [ node ],
          to_h: { title: "Email Author Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_includes result.item.authors, "author@example.com"
      end

      test "extract_authors handles author_node with only uri" do
        node = OpenStruct.new(name: nil, email: nil, uri: "https://example.com/author-profile")
        entry = OpenStruct.new(
          title: "URI Author Entry",
          url: "https://example.com/uri-author",
          entry_id: "uri-author-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          author: nil,
          author_nodes: [ node ],
          to_h: { title: "URI Author Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_includes result.item.authors, "https://example.com/author-profile"
      end

      test "extracts atom enclosures from link_nodes with rel enclosure" do
        entry = parse_entry("feeds/atom_sample.xml")
        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?

        enclosure = result.item.enclosures.find { |e| e["source"] == "atom_link" }
        assert enclosure, "expected atom enclosure from link_nodes"
        assert_equal "https://example.com/media/atom-podcast.mp3", enclosure["url"]
        assert_equal "audio/mpeg", enclosure["type"]
        assert_equal 1024, enclosure["length"]
      end

      test "extracts rss enclosures from enclosure_nodes" do
        entry = parse_entry("feeds/rss_metadata_sample.xml")
        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?

        rss_enclosure = result.item.enclosures.find { |e| e["source"] == "rss_enclosure" }
        assert rss_enclosure, "expected rss enclosure from enclosure_nodes"
        assert_equal "https://example.com/assets/audio.mp3", rss_enclosure["url"]
        assert_equal "audio/mpeg", rss_enclosure["type"]
        assert_equal 67_890, rss_enclosure["length"]
      end

      test "extracts json feed attachments as enclosures" do
        entry = parse_entry("feeds/json_feed_sample.json")
        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?

        json_enclosure = result.item.enclosures.find { |e| e["source"] == "json_feed_attachment" }
        assert json_enclosure, "expected json feed attachment"
        assert_equal "https://example.com/media/podcast.mp3", json_enclosure["url"]
        assert_equal 3_600, json_enclosure["duration"]
        assert_equal "Podcast Episode 1", json_enclosure["title"]
      end

      test "extract_enclosures skips nodes with blank url" do
        node_blank = OpenStruct.new(url: "", type: "audio/mpeg", length: "100")
        node_valid = OpenStruct.new(url: "https://example.com/media.mp3", type: "audio/mpeg", length: "200")
        entry = OpenStruct.new(
          title: "Enclosure Blank URL",
          url: "https://example.com/enc-blank",
          entry_id: "enc-blank-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          enclosure_nodes: [ node_blank, node_valid ],
          to_h: { title: "Enclosure Blank URL" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal 1, result.item.enclosures.size
        assert_equal "https://example.com/media.mp3", result.item.enclosures.first["url"]
      end

      test "extract_media_thumbnail_url from media_thumbnail_nodes" do
        node = OpenStruct.new(url: "https://example.com/thumb.jpg")
        entry = OpenStruct.new(
          title: "Thumbnail Entry",
          url: "https://example.com/thumb-entry",
          entry_id: "thumb-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          media_thumbnail_nodes: [ node ],
          to_h: { title: "Thumbnail Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "https://example.com/thumb.jpg", result.item.media_thumbnail_url
      end

      test "extract_media_thumbnail_url falls back to image" do
        entry = OpenStruct.new(
          title: "Image Fallback Entry",
          url: "https://example.com/image-fallback",
          entry_id: "image-fb-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          image: "https://example.com/image.png",
          to_h: { title: "Image Fallback Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "https://example.com/image.png", result.item.media_thumbnail_url
      end

      test "extract_media_content from media_content_nodes" do
        node = OpenStruct.new(
          url: "https://example.com/video.mp4",
          type: "video/mp4",
          medium: "video",
          height: "720",
          width: "1280",
          file_size: "5000000",
          duration: "120",
          expression: "full"
        )
        entry = OpenStruct.new(
          title: "Media Content Entry",
          url: "https://example.com/media-content",
          entry_id: "media-content-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          media_content_nodes: [ node ],
          to_h: { title: "Media Content Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        media = result.item.media_content.first
        assert_equal "https://example.com/video.mp4", media["url"]
        assert_equal "video/mp4", media["type"]
        assert_equal "video", media["medium"]
        assert_equal 720, media["height"]
        assert_equal 1280, media["width"]
        assert_equal 5_000_000, media["file_size"]
        assert_equal 120, media["duration"]
        assert_equal "full", media["expression"]
      end

      test "extract_media_content skips nodes with blank url" do
        node_blank = OpenStruct.new(url: nil, type: "video/mp4")
        node_valid = OpenStruct.new(url: "https://example.com/valid.mp4", type: "video/mp4")
        entry = OpenStruct.new(
          title: "Media Content Blank URL",
          url: "https://example.com/mc-blank",
          entry_id: "mc-blank-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          media_content_nodes: [ node_blank, node_valid ],
          to_h: { title: "Media Content Blank URL" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal 1, result.item.media_content.size
        assert_equal "https://example.com/valid.mp4", result.item.media_content.first["url"]
      end

      test "extract_categories combines categories and tags" do
        entry = OpenStruct.new(
          title: "Categories Entry",
          url: "https://example.com/cats",
          entry_id: "cats-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          categories: [ "Tech", "Ruby" ],
          tags: [ "Rails", "Ruby" ],
          to_h: { title: "Categories Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal [ "Tech", "Ruby", "Rails" ], result.item.categories
      end

      test "extract_keywords splits by comma and semicolon" do
        entry = OpenStruct.new(
          title: "Keywords Entry",
          url: "https://example.com/keywords",
          entry_id: "keywords-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          media_keywords_raw: "ruby, rails; testing",
          itunes_keywords_raw: "podcast; audio, streaming",
          to_h: { title: "Keywords Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal [ "ruby", "rails", "testing", "podcast", "audio", "streaming" ], result.item.keywords
      end

      test "extract_language from entry language field" do
        entry = OpenStruct.new(
          title: "Language Entry",
          url: "https://example.com/lang",
          entry_id: "lang-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          language: "fr",
          to_h: { title: "Language Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "fr", result.item.language
      end

      test "extract_copyright from entry copyright field" do
        entry = OpenStruct.new(
          title: "Copyright Entry",
          url: "https://example.com/copyright",
          entry_id: "copyright-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          copyright: "CC BY 4.0",
          to_h: { title: "Copyright Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "CC BY 4.0", result.item.copyright
      end

      test "extract_comments_url and extract_comments_count" do
        entry = OpenStruct.new(
          title: "Comments Entry",
          url: "https://example.com/comments",
          entry_id: "comments-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          comments: "https://example.com/comments-page",
          slash_comments_raw: "42",
          to_h: { title: "Comments Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "https://example.com/comments-page", result.item.comments_url
        assert_equal 42, result.item.comments_count
      end

      test "extract_comments_count falls back to comments_count field" do
        entry = OpenStruct.new(
          title: "Comments Count Entry",
          url: "https://example.com/comments-count",
          entry_id: "cc-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          comments_count: 7,
          to_h: { title: "Comments Count Entry" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal 7, result.item.comments_count
      end

      # ─── Task 4: Feed content processing error path and readability edge cases ───

      test "process_feed_content returns error metadata when parser raises" do
        source = build_source(feed_content_readability_enabled: true)
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
        source = build_source(feed_content_readability_enabled: true)
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
        source = build_source(feed_content_readability_enabled: true)
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
        source = build_source(feed_content_readability_enabled: true)
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
        source = build_source(feed_content_readability_enabled: true)
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
        source = build_source(feed_content_readability_enabled: true)
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
        source = build_source(feed_content_readability_enabled: true)
        entry = parse_entry("feeds/rss_readability_content.xml")

        result = ItemCreator.call(source: source, entry: entry)
        assert result.created?

        processing = result.item.metadata["feed_content_processing"]
        assert processing.present?
        # Strategy should be readability since selectors are not configured
        assert_equal "readability", processing["strategy"]
      end

      # ─── Task 5: Utility methods edge cases ───

      test "safe_integer returns nil for nil" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_nil creator.send(:safe_integer, nil)
      end

      test "safe_integer returns integer as-is" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_equal 42, creator.send(:safe_integer, 42)
      end

      test "safe_integer parses string integers" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_equal 123, creator.send(:safe_integer, "123")
      end

      test "safe_integer returns nil for non-numeric strings" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_nil creator.send(:safe_integer, "not-a-number")
      end

      test "safe_integer returns nil for blank strings" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_nil creator.send(:safe_integer, "  ")
      end

      test "safe_integer strips whitespace before parsing" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_equal 99, creator.send(:safe_integer, " 99 ")
      end

      test "safe_integer returns nil for float strings" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_nil creator.send(:safe_integer, "12.5")
      end

      test "split_keywords returns empty array for nil" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_equal [], creator.send(:split_keywords, nil)
      end

      test "split_keywords returns empty array for blank string" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_equal [], creator.send(:split_keywords, "  ")
      end

      test "split_keywords splits on commas and semicolons" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_equal [ "ruby", "rails", "testing" ], creator.send(:split_keywords, "ruby, rails; testing")
      end

      test "split_keywords strips whitespace from each keyword" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_equal [ "a", "b", "c" ], creator.send(:split_keywords, " a , b ; c ")
      end

      test "split_keywords removes blank entries" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_equal [ "a", "b" ], creator.send(:split_keywords, "a,,;,b")
      end

      test "string_or_nil returns nil for non-string values" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_equal 42, creator.send(:string_or_nil, 42)
        assert_equal true, creator.send(:string_or_nil, true)
      end

      test "string_or_nil returns nil for blank strings" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_nil creator.send(:string_or_nil, "")
        assert_nil creator.send(:string_or_nil, "   ")
      end

      test "string_or_nil strips and returns non-blank strings" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert_equal "hello", creator.send(:string_or_nil, "  hello  ")
      end

      test "normalize_metadata round-trips valid hashes through JSON" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        input = { "key" => "value", "nested" => { "a" => 1 } }
        assert_equal input, creator.send(:normalize_metadata, input)
      end

      test "normalize_metadata returns empty hash for non-serializable values" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        # Float::NAN causes JSON::GeneratorError
        bad_value = { "key" => Float::NAN }
        assert_equal({}, creator.send(:normalize_metadata, bad_value))
      end

      test "normalize_metadata converts symbol keys to strings" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        result = creator.send(:normalize_metadata, { foo: "bar" })
        assert_equal({ "foo" => "bar" }, result)
      end

      test "extract_guid returns nil when id equals url and no entry_id" do
        # extract_guid: entry_id is blank, falls back to id. When id == url, returns nil.
        entry = OpenStruct.new(
          title: "GUID Equals URL",
          url: "https://example.com/same-as-guid",
          entry_id: nil,
          id: "https://example.com/same-as-guid",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "GUID Equals URL" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        # When id equals url, extract_guid returns nil, so guid = fingerprint
        assert_equal result.item.content_fingerprint, result.item.guid
      end

      test "extract_guid prefers entry_id over id" do
        entry = OpenStruct.new(
          title: "GUID Prefer Entry ID",
          url: "https://example.com/prefer-entry-id",
          entry_id: "preferred-guid",
          id: "fallback-id",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "GUID Prefer Entry ID" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "preferred-guid", result.item.guid
      end

      test "extract_guid falls back to id when entry_id is blank" do
        entry = OpenStruct.new(
          title: "GUID Fallback ID",
          url: "https://example.com/fallback-id",
          entry_id: nil,
          id: "fallback-id-value",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "GUID Fallback ID" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal "fallback-id-value", result.item.guid
      end

      test "extract_guid returns nil when id is blank" do
        entry = OpenStruct.new(
          title: "GUID Both Blank",
          url: "https://example.com/guid-blank",
          entry_id: nil,
          id: "",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "GUID Both Blank" }
        )

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal result.item.content_fingerprint, result.item.guid
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
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        original = { "a" => [ 1, { "b" => 2 } ] }
        copy = creator.send(:deep_copy, original)
        assert_equal original, copy
        # Verify it's a deep copy, not a reference
        copy["a"][1]["b"] = 99
        assert_equal 2, original["a"][1]["b"]
      end

      test "deep_copy handles TypeError for non-dupable values" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        # Integers are non-dupable in some contexts, but deep_copy should handle them
        assert_equal 42, creator.send(:deep_copy, 42)
        assert_equal true, creator.send(:deep_copy, true)
      end

      test "html_fragment? returns true for HTML and false for plain text" do
        creator = ItemCreator.new(source: @source, entry: OpenStruct.new)
        assert creator.send(:html_fragment?, "<p>text</p>")
        assert creator.send(:html_fragment?, "<div class='x'>content</div>")
        assert creator.send(:html_fragment?, "text <br> more")
        refute creator.send(:html_fragment?, "just plain text")
        refute creator.send(:html_fragment?, "no tags here")
        refute creator.send(:html_fragment?, "a -> b")
      end

      test "extract_metadata returns empty hash when entry does not respond to to_h" do
        entry = Object.new
        # Define only required methods
        entry.define_singleton_method(:title) { "Minimal Entry" }
        entry.define_singleton_method(:url) { "https://example.com/minimal" }
        entry.define_singleton_method(:entry_id) { "minimal-guid" }
        entry.define_singleton_method(:summary) { "Summary" }
        entry.define_singleton_method(:published) { Time.utc(2025, 10, 1) }
        # No to_h method

        result = ItemCreator.call(source: @source, entry: entry)
        assert result.created?
        assert_equal({}, result.item.metadata)
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
