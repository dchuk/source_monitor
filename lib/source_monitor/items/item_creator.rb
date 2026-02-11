# frozen_string_literal: true

require "digest"
require "json"
require "cgi"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/time"
require "source_monitor/instrumentation"
require "source_monitor/scrapers/readability"
require "source_monitor/items/item_creator/entry_parser"
require "source_monitor/items/item_creator/content_extractor"

module SourceMonitor
  module Items
    class ItemCreator
      Result = Struct.new(:item, :status, :matched_by, keyword_init: true) do
        def created?
          status == :created
        end

        def updated?
          status == :updated
        end
      end

      FINGERPRINT_SEPARATOR = "\u0000".freeze
      CONTENT_METHODS = %i[content content_encoded summary].freeze
      TIMESTAMP_METHODS = %i[published updated].freeze
      KEYWORD_SEPARATORS = /[,;]+/.freeze
      METADATA_ROOT_KEY = "feedjira_entry".freeze

      def self.call(source:, entry:)
        new(source:, entry:).call
      end

      def initialize(source:, entry:)
        @source = source
        @entry = entry
      end

      def call
        attributes = build_attributes
        raw_guid = attributes[:guid]
        attributes[:guid] = raw_guid.presence || attributes[:content_fingerprint]

        existing_item, matched_by = existing_item_for(attributes, raw_guid_present: raw_guid.present?)

        if existing_item
          updated_item = update_existing_item(existing_item, attributes, matched_by)
          return Result.new(item: updated_item, status: :updated, matched_by: matched_by)
        end

        create_new_item(attributes, raw_guid_present: raw_guid.present?)
      end

      private

      attr_reader :source, :entry

      def existing_item_for(attributes, raw_guid_present:)
        guid = attributes[:guid]
        fingerprint = attributes[:content_fingerprint]

        if raw_guid_present
          existing = find_item_by_guid(guid)
          return [ existing, :guid ] if existing
        end

        if fingerprint.present?
          existing = find_item_by_fingerprint(fingerprint)
          return [ existing, :fingerprint ] if existing
        end

        [ nil, nil ]
      end

      def find_item_by_guid(guid)
        return if guid.blank?

        source.all_items.where("LOWER(guid) = ?", guid.downcase).first
      end

      def find_item_by_fingerprint(fingerprint)
        return if fingerprint.blank?

        source.all_items.find_by(content_fingerprint: fingerprint)
      end

      def instrument_duplicate(item, matched_by)
        return unless matched_by

        SourceMonitor::Instrumentation.item_duplicate(
          source_id: source.id,
          item_id: item.id,
          guid: item.guid,
          content_fingerprint: item.content_fingerprint,
          matched_by: matched_by
        )
      end

      def update_existing_item(existing_item, attributes, matched_by)
        apply_attributes(existing_item, attributes)
        existing_item.save!
        instrument_duplicate(existing_item, matched_by)
        existing_item
      end

      def create_new_item(attributes, raw_guid_present:)
        new_item = source.items.new
        apply_attributes(new_item, attributes)
        new_item.save!
        Result.new(item: new_item, status: :created)
      rescue ActiveRecord::RecordNotUnique
        handle_concurrent_duplicate(attributes, raw_guid_present:)
      end

      def handle_concurrent_duplicate(attributes, raw_guid_present:)
        matched_by = raw_guid_present ? :guid : :fingerprint
        existing = find_conflicting_item(attributes, matched_by)
        updated = update_existing_item(existing, attributes, matched_by)
        Result.new(item: updated, status: :updated, matched_by: matched_by)
      end

      def find_conflicting_item(attributes, matched_by)
        case matched_by
        when :guid
          find_item_by_guid(attributes[:guid]) || source.all_items.find_by!(guid: attributes[:guid])
        else
          fingerprint = attributes[:content_fingerprint]
          find_item_by_fingerprint(fingerprint) || source.all_items.find_by!(content_fingerprint: fingerprint)
        end
      end

      def apply_attributes(record, attributes)
        attributes = attributes.dup
        metadata = attributes.delete(:metadata)
        record.assign_attributes(attributes)
        record.metadata = metadata if metadata
      end

      def build_attributes
        entry_parser.parse
      end

      def entry_parser
        @entry_parser ||= EntryParser.new(source: source, entry: entry, content_extractor: content_extractor)
      end

      def content_extractor
        @content_extractor ||= ContentExtractor.new(source: source)
      end

      # Forwarding methods for backward compatibility with tests
      def process_feed_content(raw_content, title:) = content_extractor.process_feed_content(raw_content, title: title)
      def should_process_feed_content?(raw_content) = content_extractor.should_process_feed_content?(raw_content)
      def feed_content_parser_class = content_extractor.feed_content_parser_class
      def wrap_content_for_readability(content, title:) = content_extractor.wrap_content_for_readability(content, title: title)
      def default_feed_readability_options = content_extractor.default_feed_readability_options
      def build_feed_content_metadata(result:, raw_content:, processed_content:)
        content_extractor.build_feed_content_metadata(result: result, raw_content: raw_content, processed_content: processed_content)
      end
      def html_fragment?(value) = content_extractor.html_fragment?(value)
      def deep_copy(value) = content_extractor.deep_copy(value)
      def string_or_nil(value) = entry_parser.string_or_nil(value)
      def sanitize_string_array(values) = entry_parser.sanitize_string_array(values)
      def split_keywords(value) = entry_parser.split_keywords(value)
      def safe_integer(value) = entry_parser.safe_integer(value)
      def json_entry? = entry_parser.json_entry?
      def atom_entry? = entry_parser.atom_entry?
      def normalize_metadata(value) = entry_parser.normalize_metadata(value)
      def generate_fingerprint(title, url, content) = entry_parser.generate_fingerprint(title, url, content)
    end
  end
end
