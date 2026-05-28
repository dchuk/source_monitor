# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "source_monitor/items/item_creator/entry_parser"
require "source_monitor/items/item_creator/content_extractor"

module SourceMonitor
  module Items
    class NormalizedEntry
      def self.call(source:, entry:, content_extractor: nil)
        new(source: source, entry: entry, content_extractor: content_extractor).item_attributes
      end

      def initialize(source:, entry:, content_extractor: nil)
        @source = source
        @entry = entry
        @content_extractor = content_extractor || ItemCreator::ContentExtractor.new(source: source)
      end

      def attributes
        @attributes ||= parser.parse
      end

      def item_attributes
        attributes.merge(guid: item_guid)
      end

      def raw_guid
        attributes[:guid]
      end

      def normalized_guid
        raw_guid.present? ? raw_guid.downcase : nil
      end

      def raw_guid_present?
        normalized_guid.present?
      end

      def item_guid
        normalized_guid.presence || content_fingerprint
      end

      def content_fingerprint
        attributes[:content_fingerprint]
      end

      private

      attr_reader :source, :entry, :content_extractor

      def parser
        @parser ||= ItemCreator::EntryParser.new(
          source: source,
          entry: entry,
          content_extractor: content_extractor
        )
      end
    end
  end
end
