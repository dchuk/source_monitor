# frozen_string_literal: true

module SourceMonitor
  class DownloadContentImagesJob < ApplicationJob
    source_monitor_queue :fetch

    discard_on ActiveJob::DeserializationError

    def perform(item_id)
      item = SourceMonitor::Item.find_by(id: item_id)
      return unless item
      return unless SourceMonitor.config.images.download_enabled?

      html = item.content
      return if html.blank?

      # Build or find item_content for attachment storage
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

        # Generate a serving URL for the blob
        url_mapping[image_url] = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
      rescue StandardError
        # Individual image failure should not block others.
        # Original URL will be preserved (graceful fallback).
        next
      end

      url_mapping
    end
  end
end
