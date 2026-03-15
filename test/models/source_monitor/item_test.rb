# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ItemTest < ActiveSupport::TestCase
    setup do
      @source = Source.create!(name: "Example", feed_url: "https://example.com/feed")
    end

    test "is valid with minimal attributes" do
      item = Item.new(source: @source, guid: "abc-123", url: "HTTPS://Example.com/article")

      assert item.valid?
      assert_equal "https://example.com/article", item.url
    end

    test "normalizes optional URLs" do
      item = Item.create!(
        source: @source,
        guid: "abc-124",
        url: "http://Example.com/article",
        canonical_url: "HTTPS://Example.com/article",
        comments_url: "https://Example.com/comments"
      )

      assert_equal "http://example.com/article", item.reload.url
      assert_equal "https://example.com/article", item.canonical_url
      assert_equal "https://example.com/comments", item.comments_url
    end

    test "requires guid uniqueness per source" do
      Item.create!(source: @source, guid: "duplicate", url: "https://example.com/one")

      duplicate = Item.new(source: @source, guid: "duplicate", url: "https://example.com/two")

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:guid], "has already been taken"

      other_source = Source.create!(name: "Another", feed_url: "https://example.com/feed-two")
      different = Item.new(source: other_source, guid: "duplicate", url: "https://example.com/three")

      assert different.valid?
    end

    test "scopes provide expected subsets" do
      recent = Item.create!(source: @source, guid: "recent", url: "https://example.com/recent", published_at: 1.minute.ago)
      unpublished = Item.create!(source: @source, guid: "draft", url: "https://example.com/draft")
      failed = Item.create!(source: @source, guid: "failed", url: "https://example.com/failed", scrape_status: "failed", scraped_at: 2.minutes.ago)

      assert_includes Item.published, recent
      assert_not_includes Item.published, unpublished

      assert_includes Item.pending_scrape, unpublished
      assert_not_includes Item.pending_scrape, failed

      assert_includes Item.failed_scrape, failed

      assert_equal [ recent, failed, unpublished ], Item.where(source: @source).recent.to_a
    end

    test "increments counter cache when created" do
      assert_difference("@source.reload.items_count", 1) do
        Item.create!(source: @source, guid: "counter", url: "https://example.com/counter")
      end
    end

    test "persists scraped html and content via associated record" do
      item = Item.create!(source: @source, guid: "scraped", url: "https://example.com/scraped")

      assert_difference("SourceMonitor::ItemContent.count", 1) do
        item.update!(scraped_html: "<article>Content</article>", scraped_content: "Content")
      end

      item.reload
      assert item.item_content.present?
      assert_equal "<article>Content</article>", item.scraped_html
      assert_equal "Content", item.scraped_content
    end

    test "removes associated content when both fields cleared" do
      item = Item.create!(
        source: @source,
        guid: "scraped-cleared",
        url: "https://example.com/scraped-cleared",
        scraped_html: "<div>html</div>",
        scraped_content: "plain"
      )

      assert item.item_content.persisted?

      assert_difference("SourceMonitor::ItemContent.count", -1) do
        item.update!(scraped_html: nil, scraped_content: nil)
      end

      item.reload
      assert_nil item.scraped_html
      assert_nil item.scraped_content
    end

    test "prevents invalid URLs" do
      item = Item.new(source: @source, guid: "bad-url", url: "ftp://example.com/article")

      assert_not item.valid?
      assert_includes item.errors[:url], "must be a valid HTTP(S) URL"

      item.url = "https://example.com/article"
      item.comments_url = "mailto:info@example.com"

      assert_not item.valid?
      assert_includes item.errors[:comments_url], "must be a valid HTTP(S) URL"
    end

    test "soft_delete! decrements counter cache" do
      item = Item.create!(source: @source, guid: "to-delete", url: "https://example.com/to-delete")
      @source.reload
      initial_count = @source.items_count

      assert_difference("@source.reload.items_count", -1) do
        item.soft_delete!
      end

      assert item.deleted?
      assert_equal initial_count - 1, @source.reload.items_count
    end

    test "soft_delete! updates both deleted_at and counter atomically" do
      item = Item.create!(source: @source, guid: "transact", url: "https://example.com/transact")
      initial_count = @source.reload.items_count

      item.soft_delete!

      # Both should succeed together - item is deleted and counter decremented
      assert item.deleted?
      assert_equal initial_count - 1, @source.reload.items_count
    end

    # ─── ensure_feed_content_record callback ───

    test "creating item with content auto-creates ItemContent" do
      item = Item.create!(source: @source, guid: "feed-content", url: "https://example.com/feed-content", content: "<p>Some feed content</p>")

      item.reload
      assert item.item_content.present?
      assert item.item_content.feed_word_count.present?
      assert_equal 3, item.item_content.feed_word_count
    end

    test "creating item without content does not create ItemContent" do
      item = Item.create!(source: @source, guid: "no-content", url: "https://example.com/no-content")

      item.reload
      assert_nil item.item_content
    end

    test "ensure_feed_content_record is idempotent" do
      item = Item.create!(source: @source, guid: "has-content", url: "https://example.com/has-content", content: "<p>Feed text</p>")
      item.reload

      assert item.item_content.present?

      assert_no_difference("SourceMonitor::ItemContent.count") do
        item.ensure_feed_content_record
      end
    end

    test "ensure_feed_content_record no-ops when content is blank" do
      item = Item.create!(source: @source, guid: "no-content-manual", url: "https://example.com/no-content-manual")

      assert_no_difference("SourceMonitor::ItemContent.count") do
        item.ensure_feed_content_record
      end
    end

    test "cleanup_item_content_if_blank preserves ItemContent when item has feed content" do
      item = Item.create!(
        source: @source,
        guid: "preserve-content",
        url: "https://example.com/preserve-content",
        content: "<p>Feed content here</p>",
        scraped_html: "<div>scraped</div>",
        scraped_content: "scraped"
      )

      assert item.item_content.persisted?

      # Clear scraped fields - ItemContent should be preserved because item has feed content
      assert_no_difference("SourceMonitor::ItemContent.count") do
        item.update!(scraped_html: nil, scraped_content: nil)
      end

      item.reload
      assert item.item_content.present?
    end

    test "restore! clears deleted_at and increments counter cache" do
      item = Item.create!(source: @source, guid: "restore-test", url: "https://example.com/restore-test")
      @source.reload

      item.soft_delete!
      assert item.deleted?
      count_after_delete = @source.reload.items_count

      item.restore!
      item.reload

      assert_not item.deleted?
      assert_nil item.deleted_at
      assert_equal count_after_delete + 1, @source.reload.items_count
    end

    test "restore! is idempotent on non-deleted items" do
      item = Item.create!(source: @source, guid: "restore-noop", url: "https://example.com/restore-noop")
      @source.reload
      initial_count = @source.items_count

      item.restore!

      assert_equal initial_count, @source.reload.items_count
      assert_not item.deleted?
    end

    test "soft_delete! and restore! maintain counter cache symmetry" do
      item = Item.create!(source: @source, guid: "symmetry", url: "https://example.com/symmetry")
      @source.reload
      original_count = @source.items_count

      item.soft_delete!
      assert_equal original_count - 1, @source.reload.items_count

      item.restore!
      assert_equal original_count, @source.reload.items_count
    end

    test "soft_delete! does not double-delete" do
      item = Item.create!(source: @source, guid: "double", url: "https://example.com/double")
      @source.reload

      item.soft_delete!
      initial_count = @source.reload.items_count

      assert_no_difference("@source.reload.items_count") do
        item.soft_delete!
      end

      assert_equal initial_count, @source.reload.items_count
    end
  end
end
