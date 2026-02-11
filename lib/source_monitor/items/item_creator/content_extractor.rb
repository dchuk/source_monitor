# frozen_string_literal: true

require "cgi"

module SourceMonitor
  module Items
    class ItemCreator
      class ContentExtractor
        attr_reader :source

        def initialize(source:)
          @source = source
        end

        def process_feed_content(raw_content, title:)
          return [ raw_content, nil ] unless should_process_feed_content?(raw_content)

          parser = feed_content_parser_class.new
          html = wrap_content_for_readability(raw_content, title: title)
          result = parser.parse(html: html, readability: default_feed_readability_options)

          processed_content = result.content.presence || raw_content
          metadata = build_feed_content_metadata(result: result, raw_content: raw_content, processed_content: processed_content)

          [ processed_content, metadata.presence ]
        rescue StandardError => error
          metadata = {
            "status" => "failed",
            "strategy" => "readability",
            "applied" => false,
            "changed" => false,
            "error_class" => error.class.name,
            "error_message" => error.message
          }
          [ raw_content, metadata ]
        end

        def should_process_feed_content?(raw_content)
          source.respond_to?(:feed_content_readability_enabled?) &&
            source.feed_content_readability_enabled? &&
            raw_content.present? &&
            html_fragment?(raw_content)
        end

        def feed_content_parser_class
          SourceMonitor::Scrapers::Parsers::ReadabilityParser
        end

        def wrap_content_for_readability(content, title:)
          safe_title = title.present? ? CGI.escapeHTML(title) : "Feed Entry"
          <<~HTML
            <!DOCTYPE html>
            <html>
              <head>
                <meta charset="utf-8">
                <title>#{safe_title}</title>
              </head>
              <body>
                #{content}
              </body>
            </html>
          HTML
        end

        def default_feed_readability_options
          default = SourceMonitor::Scrapers::Readability.default_settings[:readability]
          return {} unless default

          deep_copy(default)
        end

        def build_feed_content_metadata(result:, raw_content:, processed_content:)
          metadata = {
            "strategy" => result.strategy&.to_s,
            "status" => result.status&.to_s,
            "applied" => result.content.present?,
            "changed" => processed_content != raw_content
          }

          if result.metadata && result.metadata[:readability_text_length]
            metadata["readability_text_length"] = result.metadata[:readability_text_length]
          end

          metadata["title"] = result.title if result.title.present?
          metadata.compact
        end

        def html_fragment?(value)
          value.to_s.match?(/<\s*\w+/)
        end

        def deep_copy(value)
          if value.respond_to?(:deep_dup)
            return value.deep_dup
          end

          case value
          when Hash
            value.each_with_object(value.class.new) do |(key, nested), copy|
              copy[key] = deep_copy(nested)
            end
          when Array
            value.map { |element| deep_copy(element) }
          else
            value.dup
          end
        rescue TypeError
          value
        end
      end
    end
  end
end
