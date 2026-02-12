# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Fetching
    class FeedFetcher
      class EntryProcessorImageDownloadTest < ActiveJob::TestCase
        setup do
          SourceMonitor.reset_configuration!
          @source = create_source!
        end

        test "enqueues DownloadContentImagesJob when images download enabled and item created with content" do
          SourceMonitor.configure { |c| c.images.download_to_active_storage = true }

          item = create_item!(source: @source, content: '<p><img src="https://cdn.example.com/photo.png"></p>')
          feed = build_feed_with_entry(item)

          stub_item_creator(item: item, status: :created) do
            result = EntryProcessor.new(source: @source).process_feed_entries(feed)
            assert_equal 1, result.created
          end

          assert_enqueued_with(job: SourceMonitor::DownloadContentImagesJob, args: [ item.id ])
        end

        test "does not enqueue job when images download disabled (default)" do
          item = create_item!(source: @source, content: '<p><img src="https://cdn.example.com/photo.png"></p>')
          feed = build_feed_with_entry(item)

          stub_item_creator(item: item, status: :created) do
            EntryProcessor.new(source: @source).process_feed_entries(feed)
          end

          assert_no_enqueued_jobs(only: SourceMonitor::DownloadContentImagesJob)
        end

        test "does not enqueue job when item is updated (not created)" do
          SourceMonitor.configure { |c| c.images.download_to_active_storage = true }

          item = create_item!(source: @source, content: '<p><img src="https://cdn.example.com/photo.png"></p>')
          feed = build_feed_with_entry(item)

          stub_item_creator(item: item, status: :updated) do
            result = EntryProcessor.new(source: @source).process_feed_entries(feed)
            assert_equal 1, result.updated
          end

          assert_no_enqueued_jobs(only: SourceMonitor::DownloadContentImagesJob)
        end

        test "does not enqueue job when item content is blank" do
          SourceMonitor.configure { |c| c.images.download_to_active_storage = true }

          item = create_item!(source: @source, content: nil)
          feed = build_feed_with_entry(item)

          stub_item_creator(item: item, status: :created) do
            EntryProcessor.new(source: @source).process_feed_entries(feed)
          end

          assert_no_enqueued_jobs(only: SourceMonitor::DownloadContentImagesJob)
        end

        test "enqueue failure does not break feed processing" do
          SourceMonitor.configure { |c| c.images.download_to_active_storage = true }

          item = create_item!(source: @source, content: '<p><img src="https://cdn.example.com/photo.png"></p>')
          feed = build_feed_with_entry(item)

          # Force perform_later to raise an error
          SourceMonitor::DownloadContentImagesJob.stub(:perform_later, ->(_id) { raise "enqueue error" }) do
            stub_item_creator(item: item, status: :created) do
              result = EntryProcessor.new(source: @source).process_feed_entries(feed)
              # Feed processing still succeeds
              assert_equal 1, result.created
              assert_equal 0, result.failed
            end
          end
        end

        private

        def create_item!(source:, content: nil)
          SourceMonitor::Item.create!(
            source: source,
            guid: SecureRandom.uuid,
            url: "https://example.com/#{SecureRandom.hex(6)}",
            title: "Test Article",
            content: content
          )
        end

        def build_feed_with_entry(item)
          entry = OpenStruct.new(
            entry_id: item.guid,
            title: item.title,
            url: item.url,
            content: item.content,
            summary: nil,
            published: Time.current,
            updated: nil
          )
          OpenStruct.new(entries: [ entry ])
        end

        def stub_item_creator(item:, status:)
          result = SourceMonitor::Items::ItemCreator::Result.new(
            item: item,
            status: status,
            matched_by: nil
          )
          SourceMonitor::Items::ItemCreator.stub(:call, result) do
            yield
          end
        end
      end
    end
  end
end
