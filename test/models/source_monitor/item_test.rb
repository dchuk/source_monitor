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
