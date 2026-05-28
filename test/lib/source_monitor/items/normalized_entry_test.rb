# frozen_string_literal: true

require "test_helper"
require "digest"
require "ostruct"

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

      private

      FakeContentExtractor = Struct.new(:processed_content, :metadata, keyword_init: true) do
        def process_feed_content(_raw_content, title:)
          [ processed_content, metadata ]
        end
      end

      def parse_entry(fixture)
        Feedjira.parse(File.read(file_fixture(fixture))).entries.first
      end

      def expected_fingerprint(title, url, content)
        Digest::SHA256.hexdigest([ title.to_s, url.to_s, content.to_s ].join("\u0000"))
      end
    end
  end
end
