# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "source_monitor/items/retention_pruner"

module SourceMonitor
  class ItemCleanupJobTest < ActiveJob::TestCase
    test "destroys items that violate retention policies" do
      source = create_source(items_retention_days: 5)

      travel_to Time.zone.local(2025, 10, 1, 12, 0, 0) do
        create_item(source:, guid: "old", published_at: Time.current)
      end

      travel_to Time.zone.local(2025, 10, 10, 12, 0, 0) do
        create_item(source:, guid: "recent", published_at: Time.current)

        SourceMonitor::ItemCleanupJob.perform_now(now: Time.current)

        assert_equal %w[recent], source.reload.items.pluck(:guid)
      end
    end

    test "soft deletes items when strategy requests it" do
      source = create_source(items_retention_days: 1)

      travel_to Time.zone.local(2025, 10, 1, 9, 0, 0) do
        create_item(source:, guid: "old", published_at: Time.current)
      end

      travel_to Time.zone.local(2025, 10, 3, 9, 0, 0) do
        SourceMonitor::ItemCleanupJob.perform_now(now: Time.current, soft_delete: true)

        deleted_items = source.all_items.with_deleted.where(guid: "old")
        assert_equal 1, deleted_items.count
        assert deleted_items.first.deleted?
        assert_equal 0, source.reload.items_count
      end
    end

    test "limits cleanup to selected sources" do
      target = create_source(items_retention_days: 1)
      other = create_source(items_retention_days: 1)

      travel_to Time.zone.local(2025, 10, 1, 12, 0, 0) do
        create_item(source: target, guid: "target-old", published_at: Time.current)
        create_item(source: other, guid: "other-old", published_at: Time.current)
      end

      travel_to Time.zone.local(2025, 10, 4, 12, 0, 0) do
        SourceMonitor::ItemCleanupJob.perform_now(now: Time.current, source_ids: [ target.id ])

        assert_equal [], target.reload.items.pluck(:guid)
        assert_equal [ "other-old" ], other.reload.items.pluck(:guid)
      end
    end

    private

    def create_source(attributes = {})
      defaults = {
        name: "Source #{SecureRandom.hex(4)}",
        feed_url: "https://example.com/#{SecureRandom.hex(8)}.xml",
        fetch_interval_minutes: 60
      }

      create_source!(defaults.merge(attributes))
    end

    def create_item(source:, guid:, published_at:)
      source.items.create!(
        guid: guid,
        url: "https://example.com/#{guid}",
        title: "Title #{guid}",
        published_at: published_at,
        summary: "Summary #{guid}"
      )
    end
  end
end
