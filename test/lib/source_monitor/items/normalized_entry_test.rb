# frozen_string_literal: true

require "test_helper"
require "digest"
require "ostruct"
require "securerandom"

module SourceMonitor
  module Items
    class NormalizedEntryTest < ActiveSupport::TestCase
      setup do
        clean_source_monitor_tables!
        @source = create_source!
      end

      test "normalizes RSS entry attributes without persisting an item" do
        entry = parse_entry("feeds/rss_sample.xml")

        assert_no_difference -> { SourceMonitor::Item.count } do
          normalized = NormalizedEntry.new(source: @source, entry: entry)
          attributes = normalized.attributes

          assert_equal "post-1", attributes[:guid]
          assert_equal "Hello World", attributes[:title]
          assert_equal "https://example.com/posts/1", attributes[:url]
          assert_equal attributes[:url], attributes[:canonical_url]
          assert_equal "First item content.", attributes[:content]
          assert_equal "First item content.", attributes[:summary]
          assert_equal Time.utc(2025, 10, 6, 12), attributes[:published_at]
          assert_equal expected_fingerprint(entry.title, entry.url, entry.summary), attributes[:content_fingerprint]
          assert_equal "post-1", normalized.item_attributes[:guid]
          assert_equal "Hello World", attributes.dig(:metadata, "feedjira_entry", "title")
        end
      end

      test "normalizes Atom authors categories and enclosures" do
        attributes = NormalizedEntry.call(source: @source, entry: parse_entry("feeds/atom_sample.xml"))

        assert_equal "tag:example.com,2025:atom-entry", attributes[:guid]
        assert_equal "https://example.com/posts/atom-entry", attributes[:url]
        assert_equal [ "Atom Primary Author", "Atom Secondary Author" ], attributes[:authors]
        assert_equal [ "Technology", "Atom" ], attributes[:categories]
        assert_equal [ "Technology", "Atom" ], attributes[:tags]
        assert_equal(
          [
            {
              "url" => "https://example.com/media/atom-podcast.mp3",
              "type" => "audio/mpeg",
              "length" => 1024,
              "source" => "atom_link"
            }
          ],
          attributes[:enclosures]
        )
      end

      test "normalizes JSON Feed authors tags attachments and metadata" do
        attributes = NormalizedEntry.call(source: @source, entry: parse_entry("feeds/json_feed_sample.json"))

        assert_equal "json-1", attributes[:guid]
        assert_equal "JSON Primary Author", attributes[:author]
        assert_equal [ "JSON Primary Author", "JSON Secondary Author" ], attributes[:authors]
        assert_equal [ "JSON", "Feeds" ], attributes[:categories]
        assert_equal [ "JSON", "Feeds" ], attributes[:tags]
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
          attributes[:enclosures]
        )
        assert_equal "en-US", attributes[:language]
        assert_equal "Copyright 2025 Example", attributes[:copyright]
        assert_equal "JSON Entry", attributes.dig(:metadata, "feedjira_entry", "title")
      end

      test "normalizes RSS media keywords comments and metadata" do
        attributes = NormalizedEntry.call(source: @source, entry: parse_entry("feeds/rss_metadata_sample.xml"))

        assert_equal "John Creator", attributes[:author]
        assert_equal [ "jane@example.com (Jane Author)", "John Creator" ], attributes[:authors]
        assert_equal [ "feed monitoring", "rss" ], attributes[:keywords]
        assert_equal "https://example.com/assets/thumb.jpg", attributes[:media_thumbnail_url]
        assert_equal 12, attributes[:comments_count]
        assert_equal "https://example.com/posts/1#comments", attributes[:comments_url]
        assert_equal(
          [
            {
              "url" => "https://example.com/assets/video.mp4",
              "type" => "video/mp4",
              "file_size" => 12_345
            }
          ],
          attributes[:media_content]
        )
      end

      test "captures feed content processing metadata from content extractor" do
        entry = OpenStruct.new(
          title: "Processed Entry",
          url: "https://example.com/processed",
          entry_id: "processed-guid",
          content: "<p>Raw feed content</p>",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Processed Entry" }
        )
        extractor = FakeContentExtractor.new(
          processed_content: "Processed feed content",
          metadata: {
            "status" => "failed",
            "strategy" => "readability",
            "applied" => false,
            "changed" => false
          }
        )

        attributes = NormalizedEntry.call(source: @source, entry: entry, content_extractor: extractor)

        assert_equal "Processed feed content", attributes[:content]
        assert_equal(
          {
            "status" => "failed",
            "strategy" => "readability",
            "applied" => false,
            "changed" => false
          },
          attributes.dig(:metadata, "feed_content_processing")
        )
      end

      test "falls back to fingerprint item guid when entry has no guid" do
        normalized = NormalizedEntry.new(source: @source, entry: parse_entry("feeds/rss_no_guid.xml"))

        assert_nil normalized.raw_guid
        assert_not normalized.raw_guid_present?
        assert_equal normalized.content_fingerprint, normalized.item_guid
        assert_equal normalized.content_fingerprint, normalized.item_attributes[:guid]
      end

      test "normalizes URL content and timestamp fallbacks from entry doubles" do
        alternate_link = OpenStruct.new(rel: "alternate", href: "https://example.com/via-link-node")
        first_link = OpenStruct.new(rel: "enclosure", href: "https://example.com/first-link")

        assert_equal(
          "https://example.com/via-link-node",
          normalize_entry(url: "", link_nodes: [ alternate_link ], entry_id: "link-node-guid")[:url]
        )
        assert_equal(
          "https://example.com/first-link",
          normalize_entry(url: nil, link_nodes: [ first_link ], entry_id: "first-link-guid")[:url]
        )
        assert_equal(
          "https://example.com/from-links",
          normalize_entry(url: nil, links: [ "", " ", "https://example.com/from-links" ], entry_id: "links-guid")[:url]
        )
        assert_equal(
          "Summary fallback",
          normalize_entry(content: nil, content_encoded: "", summary: "Summary fallback")[:content]
        )
        assert_equal(
          "Primary content",
          normalize_entry(content: "Primary content", content_encoded: "<p>Encoded</p>", summary: "Summary")[:content]
        )
        assert_equal(
          Time.utc(2025, 10, 5),
          normalize_entry(published: nil, updated: Time.utc(2025, 10, 5))[:published_at]
        )
        assert_nil normalize_entry(updated: nil)[:updated_at_source]
      end

      test "normalizes author media taxonomy and comment edge fields from entry doubles" do
        author_node = OpenStruct.new(name: nil, email: nil, uri: "https://example.com/author-profile")
        enclosure_blank = OpenStruct.new(url: "", type: "audio/mpeg", length: "100")
        enclosure_valid = OpenStruct.new(url: "https://example.com/media.mp3", type: "audio/mpeg", length: "200")
        thumbnail_node = OpenStruct.new(url: "https://example.com/thumb.jpg")
        media_blank = OpenStruct.new(url: nil, type: "video/mp4")
        media_valid = OpenStruct.new(
          url: "https://example.com/video.mp4",
          type: "video/mp4",
          medium: "video",
          height: "720",
          width: "1280",
          file_size: "5000000",
          duration: "120",
          expression: "full"
        )

        attributes = normalize_entry(
          author: "Same Author",
          rss_authors: [ "Same Author", "Other Author" ],
          dc_creators: [ "Creator One" ],
          author_nodes: [ author_node ],
          enclosure_nodes: [ enclosure_blank, enclosure_valid ],
          media_thumbnail_nodes: [ thumbnail_node ],
          media_content_nodes: [ media_blank, media_valid ],
          categories: [ "Tech", "Ruby" ],
          tags: [ "Rails", "Ruby" ],
          media_keywords_raw: "ruby, rails; testing",
          itunes_keywords_raw: "podcast; audio, streaming",
          language: "fr",
          copyright: "CC BY 4.0",
          comments: "https://example.com/comments",
          slash_comments_raw: "42"
        )

        assert_equal [ "Same Author", "Other Author", "Creator One", "https://example.com/author-profile" ], attributes[:authors]
        assert_equal [ { "url" => "https://example.com/media.mp3", "type" => "audio/mpeg", "length" => 200, "source" => "rss_enclosure" } ], attributes[:enclosures]
        assert_equal "https://example.com/thumb.jpg", attributes[:media_thumbnail_url]
        assert_equal(
          [
            {
              "url" => "https://example.com/video.mp4",
              "type" => "video/mp4",
              "medium" => "video",
              "height" => 720,
              "width" => 1280,
              "file_size" => 5_000_000,
              "duration" => 120,
              "expression" => "full"
            }
          ],
          attributes[:media_content]
        )
        assert_equal [ "Tech", "Ruby", "Rails" ], attributes[:categories]
        assert_equal [ "Rails", "Ruby" ], attributes[:tags]
        assert_equal [ "ruby", "rails", "testing", "podcast", "audio", "streaming" ], attributes[:keywords]
        assert_equal "fr", attributes[:language]
        assert_equal "CC BY 4.0", attributes[:copyright]
        assert_equal "https://example.com/comments", attributes[:comments_url]
        assert_equal 42, attributes[:comments_count]
      end

      test "normalizes guid fallback semantics without persistence" do
        same_as_url = NormalizedEntry.new(
          source: @source,
          entry: entry_double(url: "https://example.com/same", entry_id: nil, id: "https://example.com/same")
        )
        preferred = NormalizedEntry.new(
          source: @source,
          entry: entry_double(entry_id: "preferred-guid", id: "fallback-id")
        )
        id_fallback = NormalizedEntry.new(
          source: @source,
          entry: entry_double(entry_id: nil, id: "fallback-id-value")
        )
        blank = NormalizedEntry.new(
          source: @source,
          entry: entry_double(entry_id: nil, id: "")
        )

        assert_nil same_as_url.raw_guid
        assert_equal same_as_url.content_fingerprint, same_as_url.item_guid
        assert_equal "preferred-guid", preferred.item_guid
        assert_equal "fallback-id-value", id_fallback.item_guid
        assert_nil blank.raw_guid
        assert_equal blank.content_fingerprint, blank.item_guid
      end

      test "returns empty metadata when entry does not expose serializable metadata" do
        entry = Object.new
        entry.define_singleton_method(:title) { "Minimal Entry" }
        entry.define_singleton_method(:url) { "https://example.com/minimal" }
        entry.define_singleton_method(:entry_id) { "minimal-guid" }
        entry.define_singleton_method(:summary) { "Summary" }
        entry.define_singleton_method(:published) { Time.utc(2025, 10, 1) }

        assert_equal({}, NormalizedEntry.call(source: @source, entry: entry)[:metadata])
      end

      private

      FakeContentExtractor = Struct.new(:processed_content, :metadata, keyword_init: true) do
        def process_feed_content(_raw_content, title:)
          [ processed_content, metadata ]
        end
      end

      def parse_entry(fixture)
        Feedjira.parse(File.read(file_fixture(fixture))).entries.first
      end

      def normalize_entry(attributes = {})
        NormalizedEntry.call(source: @source, entry: entry_double(attributes))
      end

      def entry_double(attributes = {})
        defaults = {
          title: "Entry",
          url: "https://example.com/entry",
          entry_id: "entry-guid-#{SecureRandom.hex(4)}",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Entry" }
        }

        OpenStruct.new(defaults.merge(attributes))
      end

      def expected_fingerprint(title, url, content)
        Digest::SHA256.hexdigest([ title.to_s, url.to_s, content.to_s ].join("\u0000"))
      end
    end
  end
end
