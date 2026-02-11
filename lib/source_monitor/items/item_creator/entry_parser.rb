# frozen_string_literal: true

require "source_monitor/items/item_creator/entry_parser/media_extraction"

module SourceMonitor
  module Items
    class ItemCreator
      class EntryParser
        include MediaExtraction
        CONTENT_METHODS = %i[content content_encoded summary].freeze
        TIMESTAMP_METHODS = %i[published updated].freeze
        KEYWORD_SEPARATORS = /[,;]+/.freeze
        METADATA_ROOT_KEY = "feedjira_entry".freeze
        FINGERPRINT_SEPARATOR = "\u0000".freeze

        attr_reader :source, :entry

        def initialize(source:, entry:, content_extractor:)
          @source = source
          @entry = entry
          @content_extractor = content_extractor
        end

        def parse
          url = extract_url
          title = string_or_nil(entry.title) if entry.respond_to?(:title)
          raw_content = extract_content
          content, content_processing_metadata = @content_extractor.process_feed_content(raw_content, title: title)
          fingerprint = generate_fingerprint(title, url, content)
          published_at = extract_timestamp
          updated_at_source = extract_updated_timestamp

          metadata = extract_metadata
          if content_processing_metadata.present?
            metadata = metadata.merge("feed_content_processing" => content_processing_metadata)
          end

          {
            guid: extract_guid,
            title: title,
            url: url,
            canonical_url: url,
            author: extract_author,
            authors: extract_authors,
            summary: extract_summary,
            content: content,
            published_at: published_at,
            updated_at_source: updated_at_source,
            categories: extract_categories,
            tags: extract_tags,
            keywords: extract_keywords,
            enclosures: extract_enclosures,
            media_thumbnail_url: extract_media_thumbnail_url,
            media_content: extract_media_content,
            language: extract_language,
            copyright: extract_copyright,
            comments_url: extract_comments_url,
            comments_count: extract_comments_count,
            metadata: metadata,
            content_fingerprint: fingerprint
          }.compact
        end

        def extract_guid
          entry_guid = entry.respond_to?(:entry_id) ? string_or_nil(entry.entry_id) : nil
          return entry_guid if entry_guid.present?

          return unless entry.respond_to?(:id)

          entry_id = string_or_nil(entry.id)
          return if entry_id.blank?

          url = extract_url
          return entry_id if url.blank? || entry_id != url

          nil
        end

        def extract_url
          if entry.respond_to?(:url)
            primary_url = string_or_nil(entry.url)
            return primary_url if primary_url.present?
          end

          if entry.respond_to?(:link_nodes)
            alternate = Array(entry.link_nodes).find do |node|
              rel = string_or_nil(node&.rel)&.downcase
              rel.nil? || rel == "alternate"
            end
            alternate ||= Array(entry.link_nodes).first
            href = string_or_nil(alternate&.href)
            return href if href.present?
          end

          if entry.respond_to?(:links)
            href = Array(entry.links).map { |link| string_or_nil(link) }.find(&:present?)
            return href if href.present?
          end

          nil
        end

        def extract_summary
          return unless entry.respond_to?(:summary)

          string_or_nil(entry.summary)
        end

        def extract_content
          CONTENT_METHODS.each do |method|
            next unless entry.respond_to?(method)

            value = string_or_nil(entry.public_send(method))
            return value if value.present?
          end
          nil
        end

        def extract_timestamp
          TIMESTAMP_METHODS.each do |method|
            next unless entry.respond_to?(method)

            value = entry.public_send(method)
            return value if value.present?
          end
          nil
        end

        def extract_updated_timestamp
          entry.updated if entry.respond_to?(:updated) && entry.updated.present?
        end

        def extract_author
          string_or_nil(entry.author) if entry.respond_to?(:author)
        end

        def extract_authors
          values = []

          if entry.respond_to?(:rss_authors)
            values.concat(Array(entry.rss_authors).map { |value| string_or_nil(value) })
          end

          if entry.respond_to?(:dc_creators)
            values.concat(Array(entry.dc_creators).map { |value| string_or_nil(value) })
          elsif entry.respond_to?(:dc_creator)
            values << string_or_nil(entry.dc_creator)
          end

          if entry.respond_to?(:author_nodes)
            values.concat(
              Array(entry.author_nodes).map do |node|
                next unless node.respond_to?(:name) || node.respond_to?(:email) || node.respond_to?(:uri)

                string_or_nil(node.name) || string_or_nil(node.email) || string_or_nil(node.uri)
              end
            )
          end

          if json_entry?
            if entry.respond_to?(:json) && entry.json
              json_authors = Array(entry.json["authors"]).map { |author| string_or_nil(author["name"]) }
              values.concat(json_authors)
              values << string_or_nil(entry.json.dig("author", "name"))
            end
          end

          primary_author = extract_author
          values << primary_author if primary_author.present?

          values.compact.uniq
        end

        def extract_categories
          list = []
          list.concat(Array(entry.categories)) if entry.respond_to?(:categories)
          list.concat(Array(entry.tags)) if entry.respond_to?(:tags)
          if json_entry? && entry.respond_to?(:json) && entry.json
            list.concat(Array(entry.json["tags"]))
          end
          sanitize_string_array(list)
        end

        def extract_tags
          tags = []

          tags.concat(Array(entry.tags)) if entry.respond_to?(:tags)

          if json_entry? && entry.respond_to?(:json) && entry.json
            tags.concat(Array(entry.json["tags"]))
          end

          tags = extract_categories if tags.empty? && entry.respond_to?(:categories)

          sanitize_string_array(tags)
        end

        def extract_keywords
          keywords = []
          keywords.concat(split_keywords(entry.media_keywords_raw)) if entry.respond_to?(:media_keywords_raw)
          keywords.concat(split_keywords(entry.itunes_keywords_raw)) if entry.respond_to?(:itunes_keywords_raw)
          sanitize_string_array(keywords)
        end

        def extract_language
          return string_or_nil(entry.language) if entry.respond_to?(:language)

          string_or_nil(entry.json["language"]) if json_entry? && entry.respond_to?(:json) && entry.json
        end

        def extract_copyright
          return string_or_nil(entry.copyright) if entry.respond_to?(:copyright)

          string_or_nil(entry.json["copyright"]) if json_entry? && entry.respond_to?(:json) && entry.json
        end

        def extract_comments_url
          string_or_nil(entry.comments) if entry.respond_to?(:comments)
        end

        def extract_comments_count
          raw = nil
          raw ||= entry.slash_comments_raw if entry.respond_to?(:slash_comments_raw)
          raw ||= entry.comments_count if entry.respond_to?(:comments_count)
          safe_integer(raw)
        end

        def extract_metadata
          return {} unless entry.respond_to?(:to_h)

          normalized = normalize_metadata(entry.to_h)
          return {} if normalized.blank?

          { METADATA_ROOT_KEY => normalized }
        end

        def generate_fingerprint(title, url, content)
          Digest::SHA256.hexdigest(
            [
              title.to_s,
              url.to_s,
              content.to_s
            ].join(FINGERPRINT_SEPARATOR)
          )
        end

        def string_or_nil(value)
          return value unless value.is_a?(String)

          value.strip.presence
        end

        def sanitize_string_array(values)
          Array(values).map { |value| string_or_nil(value) }.compact.uniq
        end

        def split_keywords(value)
          return [] if value.nil?

          string = string_or_nil(value)
          return [] if string.blank?

          string.split(KEYWORD_SEPARATORS).map { |keyword| keyword.strip.presence }.compact
        end

        def safe_integer(value)
          return if value.nil?
          return value if value.is_a?(Integer)

          string = value.to_s.strip
          return if string.blank?

          Integer(string, 10)
        rescue ArgumentError
          nil
        end

        def json_entry?
          defined?(Feedjira::Parser::JSONFeedItem) && entry.is_a?(Feedjira::Parser::JSONFeedItem)
        end

        def atom_entry?
          defined?(Feedjira::Parser::AtomEntry) && entry.is_a?(Feedjira::Parser::AtomEntry)
        end

        def normalize_metadata(value)
          JSON.parse(JSON.generate(value))
        rescue JSON::GeneratorError, JSON::ParserError, TypeError
          {}
        end
      end
    end
  end
end
