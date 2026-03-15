# frozen_string_literal: true

require "faraday"

module SourceMonitor
  module Images
    # Orchestrates downloading images from an item's HTML content, attaching
    # them via ActiveStorage, and rewriting the HTML to use local blob URLs.
    # Extracted from DownloadContentImagesJob for testability and reuse.
    class Processor
      TRANSIENT_ERRORS = [
        Timeout::Error, Errno::ETIMEDOUT,
        Faraday::TimeoutError, Faraday::ConnectionFailed,
        Net::OpenTimeout, Net::ReadTimeout
      ].freeze

      def initialize(item)
        @item = item
      end

      def call
        return unless SourceMonitor.config.images.download_enabled?

        html = item.content
        return if html.blank?

        item_content = item.item_content || item.build_item_content

        # Skip if images already attached (idempotency)
        return if item_content.persisted? && item_content.images.attached?

        base_url = item.url
        rewriter = SourceMonitor::Images::ContentRewriter.new(html, base_url: base_url)
        image_urls = rewriter.image_urls
        return if image_urls.empty?

        # Save item_content first so we can attach blobs to it
        item_content.save! unless item_content.persisted?

        # Download images and build URL mapping
        url_mapping = download_images(item_content, image_urls)
        return if url_mapping.empty?

        # Rewrite HTML with Active Storage URLs
        rewritten_html = rewriter.rewrite do |original_url|
          url_mapping[original_url]
        end

        # Update the item content with rewritten HTML
        item.update!(content: rewritten_html)
      end

      private

      attr_reader :item

      def download_images(item_content, image_urls)
        url_mapping = {}
        settings = SourceMonitor.config.images

        image_urls.each do |image_url|
          result = SourceMonitor::Images::Downloader.new(image_url, settings: settings).call
          next unless result

          blob = ActiveStorage::Blob.create_and_upload!(
            io: result.io,
            filename: result.filename,
            content_type: result.content_type
          )
          item_content.images.attach(blob)

          url_mapping[image_url] = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
        rescue ActiveRecord::Deadlocked
          raise # let job framework retry on database deadlock
        rescue *TRANSIENT_ERRORS
          raise # re-raise transient errors to abort job for framework retry
        rescue StandardError => error
          # Individual image failure should not block others.
          # Original URL will be preserved (graceful fallback).
          log_image_error(image_url, error)
          next
        end

        url_mapping
      end

      def log_image_error(image_url, error)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        Rails.logger.warn(
          "[SourceMonitor::Images::Processor] Skipping image #{image_url}: #{error.class} - #{error.message}"
        )
      rescue StandardError
        nil
      end
    end
  end
end
