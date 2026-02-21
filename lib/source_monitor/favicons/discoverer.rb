# frozen_string_literal: true

require "faraday"
require "securerandom"
require "nokogiri"

module SourceMonitor
  module Favicons
    class Discoverer
      Result = Struct.new(:io, :filename, :content_type, :url, keyword_init: true)

      attr_reader :website_url, :settings

      def initialize(website_url, settings: nil)
        @website_url = website_url
        @settings = settings || SourceMonitor.config.favicons
      end

      def call
        return if website_url.blank?

        try_html_link_tags || try_favicon_ico || try_google_favicon_api
      rescue Faraday::Error, URI::InvalidURIError, Timeout::Error
        nil
      end

      private

      def try_favicon_ico
        uri = URI.parse(website_url)
        favicon_url = "#{uri.scheme}://#{uri.host}/favicon.ico"
        download_favicon(favicon_url)
      rescue URI::InvalidURIError
        nil
      end

      def try_html_link_tags
        response = html_client.get(website_url)
        return unless response.status == 200

        doc = Nokogiri::HTML(response.body)
        candidates = extract_icon_candidates(doc)
        return if candidates.empty?

        candidates.each do |candidate_url|
          result = download_favicon(candidate_url)
          return result if result
        end
        nil
      rescue Faraday::Error, Nokogiri::SyntaxError
        nil
      end

      def try_google_favicon_api
        uri = URI.parse(website_url)
        api_url = "https://www.google.com/s2/favicons?domain=#{uri.host}&sz=64"
        download_favicon(api_url)
      rescue URI::InvalidURIError
        nil
      end

      def extract_icon_candidates(doc)
        candidates = []

        # Search link[rel] tags for icon types
        icon_selectors = [
          'link[rel*="icon"]',
          'link[rel="apple-touch-icon"]',
          'link[rel="apple-touch-icon-precomposed"]',
          'link[rel="mask-icon"]'
        ]

        icon_selectors.each do |selector|
          doc.css(selector).each do |link|
            href = link["href"]
            next if href.blank?

            absolute_url = resolve_url(href)
            next unless absolute_url

            sizes = parse_sizes(link["sizes"])
            candidates << { url: absolute_url, size: sizes }
          end
        end

        # Search meta tags for msapplication-TileImage
        doc.css('meta[name="msapplication-TileImage"]').each do |meta|
          content = meta["content"]
          next if content.blank?

          absolute_url = resolve_url(content)
          candidates << { url: absolute_url, size: 0 } if absolute_url
        end

        # og:image as last resort
        doc.css('meta[property="og:image"]').each do |meta|
          content = meta["content"]
          next if content.blank?

          absolute_url = resolve_url(content)
          candidates << { url: absolute_url, size: -1 } if absolute_url
        end

        # Sort by size descending (prefer larger), deduplicate by URL
        candidates
          .sort_by { |c| -(c[:size] || 0) }
          .uniq { |c| c[:url] }
          .map { |c| c[:url] }
      end

      def parse_sizes(sizes_attr)
        return 0 if sizes_attr.blank?
        return 0 if sizes_attr.casecmp("any").zero?

        # Parse "32x32", "256x256", etc. -- take the max dimension
        match = sizes_attr.match(/(\d+)x(\d+)/i)
        return 0 unless match

        [ match[1].to_i, match[2].to_i ].max
      end

      def resolve_url(href)
        return nil if href.blank?

        uri = URI.parse(href)
        if uri.absolute?
          href
        else
          URI.join(website_url, href).to_s
        end
      rescue URI::InvalidURIError, URI::BadURIError
        nil
      end

      def download_favicon(url)
        response = image_client.get(url)
        return unless response.status == 200

        content_type = response.headers["content-type"]&.split(";")&.first&.strip&.downcase
        return unless content_type && settings.allowed_content_types.include?(content_type)

        body = response.body
        return unless body && body.bytesize > 0
        return if body.bytesize > settings.max_download_size

        filename = derive_filename(url, content_type)

        Result.new(
          io: StringIO.new(body),
          filename: filename,
          content_type: content_type,
          url: url
        )
      rescue Faraday::Error
        nil
      end

      def derive_filename(favicon_url, content_type)
        uri = URI.parse(favicon_url)
        basename = File.basename(uri.path) if uri.path.present?

        if basename.present? && basename.include?(".")
          basename
        else
          ext = Rack::Mime::MIME_TYPES.invert[content_type] || ".ico"
          "favicon-#{SecureRandom.hex(8)}#{ext}"
        end
      rescue URI::InvalidURIError
        ext = Rack::Mime::MIME_TYPES.invert[content_type] || ".ico"
        "favicon-#{SecureRandom.hex(8)}#{ext}"
      end

      def html_client
        build_client("text/html, application/xhtml+xml")
      end

      def image_client
        build_client("image/*")
      end

      def build_client(accept_header)
        timeout = settings.fetch_timeout

        Faraday.new do |f|
          f.options.timeout = timeout
          f.options.open_timeout = [ timeout / 2, 3 ].min
          f.headers["User-Agent"] = SourceMonitor.config.http.user_agent || "SourceMonitor/#{SourceMonitor::VERSION}"
          f.headers["Accept"] = accept_header
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
