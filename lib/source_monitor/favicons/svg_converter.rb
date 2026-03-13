# frozen_string_literal: true

module SourceMonitor
  module Favicons
    class SvgConverter
      PNG_CONTENT_TYPE = "image/png"
      DEFAULT_SIZE = 64

      # Converts an SVG string to PNG bytes using MiniMagick.
      # Returns a Hash with :io, :content_type, :filename or nil on failure.
      def self.call(svg_body, filename: "favicon.png", size: DEFAULT_SIZE)
        return nil unless defined?(MiniMagick)

        new(svg_body, filename: filename, size: size).call
      end

      def initialize(svg_body, filename:, size:)
        @svg_body = svg_body
        @filename = filename.sub(/\.svg\z/i, ".png")
        @size = size
      end

      def call
        convert_svg_to_png
      rescue StandardError => e
        log_conversion_failure(e)
        nil
      end

      private

      def convert_svg_to_png
        image = MiniMagick::Image.read(@svg_body, ".svg")
        image.format("png")
        image.resize("#{@size}x#{@size}")

        png_bytes = image.to_blob

        return nil if png_bytes.nil? || png_bytes.empty?

        {
          io: StringIO.new(png_bytes),
          content_type: PNG_CONTENT_TYPE,
          filename: @filename
        }
      ensure
        image&.destroy!
      end

      def log_conversion_failure(error)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        Rails.logger.warn(
          "[SourceMonitor::Favicons::SvgConverter] SVG conversion failed: #{error.message}"
        )
      rescue StandardError # rubocop:disable Lint/SuppressedException
      end
    end
  end
end
