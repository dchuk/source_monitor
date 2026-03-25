# frozen_string_literal: true

require "source_monitor/items/item_creator"

module SourceMonitor
  module Items
    # Builds a pre-fetched lookup index of existing items for a batch of entries.
    #
    # Instead of N individual SELECT queries (one per feed entry) to check for
    # existing items, this class:
    #   1. Pre-parses all entries to collect GUIDs + fingerprints
    #   2. Does a single WHERE guid IN (...) query to find existing items by GUID
    #   3. Does a single WHERE content_fingerprint IN (...) for remaining entries
    #   4. Returns an index hash that ItemCreator can use to skip per-entry SELECTs
    #
    # The actual item creation/update is still done by ItemCreator.call, which
    # accepts the index via the existing_items_index parameter.
    class BatchItemCreator
      # Builds a lookup index from a batch of feed entries.
      # Returns a Hash with :by_guid and :by_fingerprint keys.
      def self.build_index(source:, entries:)
        new(source: source, entries: entries).build_index
      end

      def initialize(source:, entries:)
        @source = source
        @entries = Array(entries)
      end

      def build_index
        return { by_guid: {}, by_fingerprint: {} } if @entries.empty?

        # Step 1: Pre-parse entries to extract GUIDs and fingerprints for bulk lookup.
        entry_identifiers = @entries.map do |entry|
          parser = ItemCreator::EntryParser.new(
            source: @source,
            entry: entry,
            content_extractor: content_extractor
          )
          attrs = parser.parse
          raw_guid = attrs[:guid]
          normalized_guid = raw_guid.present? ? raw_guid.downcase : nil
          guid = normalized_guid.presence || attrs[:content_fingerprint]

          { guid: guid, fingerprint: attrs[:content_fingerprint], raw_guid_present: normalized_guid.present? }
        end

        # Step 2: Batch-fetch existing items by GUID (single query)
        guids = entry_identifiers
          .select { |ei| ei[:raw_guid_present] }
          .filter_map { |ei| ei[:guid] }
          .uniq

        existing_by_guid = if guids.any?
          @source.all_items.where(guid: guids).index_by(&:guid)
        else
          {}
        end

        # Step 3: For entries without a GUID match, batch-fetch by fingerprint
        unmatched_fingerprints = entry_identifiers.filter_map do |ei|
          guid = ei[:guid]
          next if ei[:raw_guid_present] && existing_by_guid.key?(guid)

          ei[:fingerprint].presence
        end.uniq

        existing_by_fingerprint = if unmatched_fingerprints.any?
          @source.all_items
            .where(content_fingerprint: unmatched_fingerprints)
            .index_by(&:content_fingerprint)
        else
          {}
        end

        { by_guid: existing_by_guid, by_fingerprint: existing_by_fingerprint }
      end

      private

      def content_extractor
        @content_extractor ||= ItemCreator::ContentExtractor.new(source: @source)
      end
    end
  end
end
