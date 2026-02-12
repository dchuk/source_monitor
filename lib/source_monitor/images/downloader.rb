# frozen_string_literal: true

require "faraday"
require "securerandom"

module SourceMonitor
  module Images
    class Downloader
      Result = Struct.new(:io, :filename, :content_type, :byte_size, keyword_init: true)

      attr_reader :url, :settings

      def initialize(url, settings: nil)
        @url = url
        @settings = settings || SourceMonitor.config.images
      end

      # Downloads the image and returns a Result, or nil if download fails
      # or the image does not meet validation criteria.
      def call
        response = fetch_image
        return unless response

        content_type = response.headers["content-type"]&.split(";")&.first&.strip&.downcase
        return unless allowed_content_type?(content_type)

        body = response.body
        return unless body && body.bytesize > 0
        return if body.bytesize > settings.max_download_size

        filename = derive_filename(url, content_type)

        Result.new(
          io: StringIO.new(body),
          filename: filename,
          content_type: content_type,
          byte_size: body.bytesize
        )
      rescue Faraday::Error, URI::InvalidURIError, Timeout::Error
        nil
      end

      private

      def fetch_image
        connection = Faraday.new do |f|
          f.options.timeout = settings.download_timeout
          f.options.open_timeout = [ settings.download_timeout / 2, 5 ].min
          f.headers["User-Agent"] = SourceMonitor.config.http.user_agent || "SourceMonitor/#{SourceMonitor::VERSION}"
          f.headers["Accept"] = "image/*"
          f.adapter Faraday.default_adapter
        end

        response = connection.get(url)
        return response if response.status == 200

        nil
      end

      def allowed_content_type?(content_type)
        return false if content_type.blank?

        settings.allowed_content_types.include?(content_type)
      end

      def derive_filename(image_url, content_type)
        uri = URI.parse(image_url)
        basename = File.basename(uri.path) if uri.path.present?

        if basename.present? && basename.include?(".")
          basename
        else
          ext = Rack::Mime::MIME_TYPES.invert[content_type] || ".bin"
          "image-#{SecureRandom.hex(8)}#{ext}"
        end
      rescue URI::InvalidURIError
        ext = Rack::Mime::MIME_TYPES.invert[content_type] || ".bin"
        "image-#{SecureRandom.hex(8)}#{ext}"
      end
    end
  end
end
