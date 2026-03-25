# frozen_string_literal: true

require "test_helper"
require "digest"
require "securerandom"
require "ostruct"

module SourceMonitor
  module Items
    class BatchItemCreatorTest < ActiveSupport::TestCase
      setup do
        clean_source_monitor_tables!
        @source = create_source!
      end

      test "build_index returns empty hashes for empty entries" do
        index = BatchItemCreator.build_index(source: @source, entries: [])
        assert_equal({}, index[:by_guid])
        assert_equal({}, index[:by_fingerprint])
      end

      test "build_index fetches existing items by guid in bulk" do
        # Create existing items
        item1 = SourceMonitor::Item.create!(
          source: @source,
          guid: "guid-1",
          url: "https://example.com/1",
          title: "Item 1"
        )
        item2 = SourceMonitor::Item.create!(
          source: @source,
          guid: "guid-2",
          url: "https://example.com/2",
          title: "Item 2"
        )

        entries = [
          OpenStruct.new(
            entry_id: "guid-1",
            title: "Item 1",
            url: "https://example.com/1",
            summary: "Summary 1",
            published: Time.utc(2025, 10, 1),
            to_h: { title: "Item 1" }
          ),
          OpenStruct.new(
            entry_id: "guid-2",
            title: "Item 2",
            url: "https://example.com/2",
            summary: "Summary 2",
            published: Time.utc(2025, 10, 1),
            to_h: { title: "Item 2" }
          ),
          OpenStruct.new(
            entry_id: "guid-new",
            title: "New Item",
            url: "https://example.com/new",
            summary: "Summary New",
            published: Time.utc(2025, 10, 1),
            to_h: { title: "New Item" }
          )
        ]

        index = BatchItemCreator.build_index(source: @source, entries: entries)

        assert_equal item1, index[:by_guid]["guid-1"]
        assert_equal item2, index[:by_guid]["guid-2"]
        assert_nil index[:by_guid]["guid-new"]
      end

      test "build_index fetches existing items by content fingerprint" do
        # Create entry without guid that uses fingerprint
        entry = OpenStruct.new(
          title: "Fingerprint Item",
          url: "https://example.com/fp",
          summary: "Some summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Fingerprint Item" }
        )

        # Create item individually first
        first_result = ItemCreator.call(source: @source, entry: entry)
        assert first_result.created?
        existing_item = first_result.item

        # Build index with same entry -- should appear in by_fingerprint
        index = BatchItemCreator.build_index(source: @source, entries: [ entry ])

        assert_equal existing_item, index[:by_fingerprint][existing_item.content_fingerprint]
      end

      test "build_index normalizes guids to lowercase for lookup" do
        # Create item with lowercase guid
        item = SourceMonitor::Item.create!(
          source: @source,
          guid: "lower-guid",
          url: "https://example.com/item",
          title: "Item"
        )

        entries = [
          OpenStruct.new(
            entry_id: "LOWER-GUID",
            title: "Item",
            url: "https://example.com/item",
            summary: "Summary",
            published: Time.utc(2025, 10, 1),
            to_h: { title: "Item" }
          )
        ]

        index = BatchItemCreator.build_index(source: @source, entries: entries)

        assert_equal item, index[:by_guid]["lower-guid"]
      end

      test "ItemCreator.call with existing_items_index skips per-entry SELECT" do
        # Create existing item
        existing = SourceMonitor::Item.create!(
          source: @source,
          guid: "existing-guid",
          url: "https://example.com/existing",
          title: "Existing"
        )

        entry = OpenStruct.new(
          entry_id: "existing-guid",
          title: "Updated Title",
          url: "https://example.com/existing",
          summary: "Updated summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Updated Title" }
        )

        index = { by_guid: { "existing-guid" => existing }, by_fingerprint: {} }

        result = ItemCreator.call(source: @source, entry: entry, existing_items_index: index)

        # Should match existing item via the index without a DB query
        assert result.updated? || result.unchanged?
        assert_equal existing.id, result.item.id
      end

      test "ItemCreator.call with index creates new items normally" do
        entry = OpenStruct.new(
          entry_id: "brand-new-guid",
          title: "Brand New",
          url: "https://example.com/brand-new",
          summary: "Summary",
          published: Time.utc(2025, 10, 1),
          to_h: { title: "Brand New" }
        )

        index = { by_guid: {}, by_fingerprint: {} }

        result = ItemCreator.call(source: @source, entry: entry, existing_items_index: index)
        assert result.created?
        assert_equal "brand-new-guid", result.item.guid
      end

      test "full batch flow: build_index + ItemCreator.call per entry" do
        entries = 3.times.map do |i|
          OpenStruct.new(
            entry_id: "batch-guid-#{i}",
            title: "Item #{i}",
            url: "https://example.com/item-#{i}",
            summary: "Summary #{i}",
            published: Time.utc(2025, 10, 1),
            to_h: { title: "Item #{i}" }
          )
        end

        index = BatchItemCreator.build_index(source: @source, entries: entries)

        results = entries.map do |entry|
          ItemCreator.call(source: @source, entry: entry, existing_items_index: index)
        end

        assert_equal 3, results.size
        assert results.all?(&:created?)
        assert_equal 3, SourceMonitor::Item.where(source: @source).count
      end
    end
  end
end
