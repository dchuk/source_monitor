# frozen_string_literal: true

module SourceMonitor
  module Items
    class ItemCreator
      class EntryParser
        module MediaExtraction
          def extract_enclosures
            enclosures = []

            if entry.respond_to?(:enclosure_nodes)
              Array(entry.enclosure_nodes).each do |node|
                url = string_or_nil(node&.url)
                next if url.blank?

                enclosures << {
                  "url" => url,
                  "type" => string_or_nil(node&.type),
                  "length" => safe_integer(node&.length),
                  "source" => "rss_enclosure"
                }.compact
              end
            end

            if atom_entry? && entry.respond_to?(:link_nodes)
              Array(entry.link_nodes).each do |link|
                next unless string_or_nil(link&.rel)&.downcase == "enclosure"

                url = string_or_nil(link&.href)
                next if url.blank?

                enclosures << {
                  "url" => url,
                  "type" => string_or_nil(link&.type),
                  "length" => safe_integer(link&.length),
                  "source" => "atom_link"
                }.compact
              end
            end

            if json_entry? && entry.respond_to?(:json) && entry.json
              Array(entry.json["attachments"]).each do |attachment|
                url = string_or_nil(attachment["url"])
                next if url.blank?

                enclosures << {
                  "url" => url,
                  "type" => string_or_nil(attachment["mime_type"]),
                  "length" => safe_integer(attachment["size_in_bytes"]),
                  "duration" => safe_integer(attachment["duration_in_seconds"]),
                  "title" => string_or_nil(attachment["title"]),
                  "source" => "json_feed_attachment"
                }.compact
              end
            end

            enclosures.uniq
          end

          def extract_media_thumbnail_url
            if entry.respond_to?(:media_thumbnail_nodes)
              thumbnail = Array(entry.media_thumbnail_nodes).find { |node| string_or_nil(node&.url).present? }
              return string_or_nil(thumbnail&.url) if thumbnail
            end

            string_or_nil(entry.image) if entry.respond_to?(:image)
          end

          def extract_media_content
            contents = []

            if entry.respond_to?(:media_content_nodes)
              Array(entry.media_content_nodes).each do |node|
                url = string_or_nil(node&.url)
                next if url.blank?

                contents << {
                  "url" => url,
                  "type" => string_or_nil(node&.type),
                  "medium" => string_or_nil(node&.medium),
                  "height" => safe_integer(node&.height),
                  "width" => safe_integer(node&.width),
                  "file_size" => safe_integer(node&.file_size),
                  "duration" => safe_integer(node&.duration),
                  "expression" => string_or_nil(node&.expression)
                }.compact
              end
            end

            contents.uniq
          end
        end
      end
    end
  end
end
