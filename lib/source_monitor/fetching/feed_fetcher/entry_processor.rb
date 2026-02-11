# frozen_string_literal: true

module SourceMonitor
  module Fetching
    class FeedFetcher
      class EntryProcessor
        attr_reader :source

        def initialize(source:)
          @source = source
        end

        def process_feed_entries(feed)
          return FeedFetcher::EntryProcessingResult.new(
            created: 0,
            updated: 0,
            failed: 0,
            items: [],
            errors: [],
            created_items: [],
            updated_items: []
          ) unless feed.respond_to?(:entries)

          created = 0
          updated = 0
          failed = 0
          items = []
          created_items = []
          updated_items = []
          errors = []

          Array(feed.entries).each do |entry|
            begin
              result = SourceMonitor::Items::ItemCreator.call(source:, entry:)
              SourceMonitor::Events.run_item_processors(source:, entry:, result: result)
              items << result.item
              if result.created?
                created += 1
                created_items << result.item
                SourceMonitor::Events.after_item_created(item: result.item, source:, entry:, result: result)
              else
                updated += 1
                updated_items << result.item
              end
            rescue StandardError => error
              failed += 1
              errors << normalize_item_error(entry, error)
            end
          end

          FeedFetcher::EntryProcessingResult.new(
            created:,
            updated:,
            failed:,
            items:,
            errors: errors.compact,
            created_items:,
            updated_items:
          )
        end

        private

        def normalize_item_error(entry, error)
          {
            guid: safe_entry_guid(entry),
            title: safe_entry_title(entry),
            error_class: error.class.name,
            error_message: error.message
          }
        rescue StandardError
          { error_class: error.class.name, error_message: error.message }
        end

        def safe_entry_guid(entry)
          if entry.respond_to?(:entry_id)
            entry.entry_id
          elsif entry.respond_to?(:id)
            entry.id
          end
        end

        def safe_entry_title(entry)
          entry.title if entry.respond_to?(:title)
        end
      end
    end
  end
end
