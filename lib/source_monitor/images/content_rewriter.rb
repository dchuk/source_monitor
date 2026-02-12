# frozen_string_literal: true

require "nokolexbor"
require "uri"

module SourceMonitor
  module Images
    class ContentRewriter
      attr_reader :html, :base_url

      def initialize(html, base_url: nil)
        @html = html.to_s
        @base_url = base_url
      end

      # Returns an array of absolute image URLs found in <img> tags.
      # Skips data: URIs, blank src, and invalid URLs.
      def image_urls
        return [] if html.blank?

        doc = parse_fragment
        urls = []

        doc.css("img[src]").each do |img|
          url = resolve_url(img["src"])
          urls << url if url && downloadable_url?(url)
        end

        urls.uniq
      end

      # Rewrites <img src="..."> attributes by yielding each original URL
      # to the block and replacing with the block's return value.
      # Returns the rewritten HTML string.
      # If the block returns nil, the original URL is preserved (graceful fallback).
      def rewrite
        return html if html.blank?

        doc = parse_fragment

        doc.css("img[src]").each do |img|
          original_url = resolve_url(img["src"])
          next unless original_url && downloadable_url?(original_url)

          new_url = yield(original_url)
          img["src"] = new_url if new_url.present?
        end

        doc.to_html
      end

      private

      def parse_fragment
        Nokolexbor::DocumentFragment.parse(html)
      end

      def resolve_url(src)
        src = src.to_s.strip
        return nil if src.blank?
        return nil if src.start_with?("data:")

        uri = URI.parse(src)
        if uri.relative? && base_url.present?
          URI.join(base_url, src).to_s
        elsif uri.absolute?
          src
        end
      rescue URI::InvalidURIError
        nil
      end

      def downloadable_url?(url)
        uri = URI.parse(url)
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
