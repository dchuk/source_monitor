# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ItemContentTest < ActiveSupport::TestCase
    setup do
      clean_source_monitor_tables!
      @source = create_source!
      @item = SourceMonitor::Item.create!(
        source: @source,
        title: "Test Item",
        url: "https://example.com/item-#{SecureRandom.hex(4)}",
        guid: SecureRandom.uuid
      )
    end

    test "belongs to item" do
      content = SourceMonitor::ItemContent.create!(item: @item)
      assert_equal @item, content.item
    end

    test "validates presence of item" do
      content = SourceMonitor::ItemContent.new(item: nil)
      assert_not content.valid?
      assert_includes content.errors[:item], "must exist"
    end

    test "responds to images attachment" do
      content = SourceMonitor::ItemContent.new(item: @item)
      assert_respond_to content, :images
    end

    test "images returns empty collection by default" do
      content = SourceMonitor::ItemContent.create!(item: @item)
      assert_empty content.images
    end

    test "can attach an image" do
      content = SourceMonitor::ItemContent.create!(item: @item)
      content.images.attach(
        io: File.open(File.expand_path("../../fixtures/files/test_image.png", __dir__)),
        filename: "test_image.png",
        content_type: "image/png"
      )

      assert_equal 1, content.images.count
      assert_equal "test_image.png", content.images.first.filename.to_s
    end

    test "can attach multiple images" do
      content = SourceMonitor::ItemContent.create!(item: @item)
      content.images.attach(
        io: StringIO.new("fake-png-data"),
        filename: "image1.png",
        content_type: "image/png"
      )
      content.images.attach(
        io: StringIO.new("fake-jpg-data"),
        filename: "image2.jpg",
        content_type: "image/jpeg"
      )

      assert_equal 2, content.images.count
    end

    # --- Word count computation tests ---

    test "computes scraped_word_count on save when scraped_content present" do
      content = SourceMonitor::ItemContent.create!(item: @item, scraped_content: "Hello world this is a test")
      assert_equal 6, content.scraped_word_count
    end

    test "sets scraped_word_count to nil when scraped_content is blank" do
      content = SourceMonitor::ItemContent.create!(item: @item, scraped_content: "Hello world")
      assert_equal 2, content.scraped_word_count

      content.update!(scraped_content: "")
      assert_nil content.scraped_word_count
    end

    test "computes feed_word_count stripping HTML from item content" do
      @item.update!(content: "<p>Hello <strong>world</strong> this is <em>a</em> test</p>")
      content = SourceMonitor::ItemContent.create!(item: @item)
      assert_equal 6, content.feed_word_count
    end

    test "sets feed_word_count to nil when item content is blank" do
      @item.update!(content: nil)
      content = SourceMonitor::ItemContent.create!(item: @item)
      assert_nil content.feed_word_count
    end

    test "updates scraped_word_count when scraped_content changes" do
      content = SourceMonitor::ItemContent.create!(item: @item, scraped_content: "two words")
      assert_equal 2, content.scraped_word_count

      content.update!(scraped_content: "now there are four words")
      assert_equal 5, content.scraped_word_count
    end

    test "total_word_count returns max of scraped and feed word counts" do
      @item.update!(content: "<p>one two three</p>")
      content = SourceMonitor::ItemContent.create!(item: @item, scraped_content: "one two three four five")
      assert_equal 5, content.total_word_count
    end

    test "total_word_count returns 0 when both counts are nil" do
      content = SourceMonitor::ItemContent.create!(item: @item)
      assert_equal 0, content.total_word_count
    end
  end
end
