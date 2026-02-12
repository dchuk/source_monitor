# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class DownloadContentImagesJobTest < ActiveJob::TestCase
    TINY_PNG = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
      0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
      0x44, 0xAE, 0x42, 0x60, 0x82
    ].pack("C*").freeze

    IMAGE_URL = "https://cdn.example.com/photo.png"

    setup do
      SourceMonitor.reset_configuration!
      SourceMonitor.configure do |config|
        config.images.download_to_active_storage = true
      end
    end

    test "downloads images and rewrites item content HTML" do
      source = create_source!
      item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

      stub_request(:get, IMAGE_URL)
        .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

      DownloadContentImagesJob.perform_now(item.id)

      item.reload
      assert_not_includes item.content, IMAGE_URL
      assert_match %r{/rails/active_storage/blobs/}, item.content
      assert_equal 1, item.item_content.images.count
    end

    test "skips when config disabled" do
      SourceMonitor.configure do |config|
        config.images.download_to_active_storage = false
      end

      source = create_source!
      item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

      DownloadContentImagesJob.perform_now(item.id)

      item.reload
      assert_includes item.content, IMAGE_URL
    end

    test "skips when item not found" do
      assert_nothing_raised do
        DownloadContentImagesJob.perform_now(-1)
      end
    end

    test "skips when item content is blank" do
      source = create_source!
      item = create_item!(source: source, content: nil)

      assert_nothing_raised do
        DownloadContentImagesJob.perform_now(item.id)
      end
    end

    test "skips when images already attached (idempotency)" do
      source = create_source!
      item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

      stub_request(:get, IMAGE_URL)
        .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

      # First run downloads
      DownloadContentImagesJob.perform_now(item.id)
      item.reload
      first_content = item.content

      # Second run should skip
      DownloadContentImagesJob.perform_now(item.id)
      item.reload
      assert_equal first_content, item.content
      assert_equal 1, item.item_content.images.count
    end

    test "skips when no image URLs found in content" do
      source = create_source!
      item = create_item!(source: source, content: "<p>No images here</p>")

      DownloadContentImagesJob.perform_now(item.id)

      item.reload
      assert_equal "<p>No images here</p>", item.content
      assert_nil item.item_content
    end

    test "gracefully handles individual image download failure" do
      good_url = "https://cdn.example.com/good.png"
      bad_url = "https://cdn.example.com/bad.png"

      source = create_source!
      item = create_item!(
        source: source,
        content: %(<p><img src="#{good_url}"><img src="#{bad_url}"></p>)
      )

      stub_request(:get, good_url)
        .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })
      stub_request(:get, bad_url).to_timeout

      DownloadContentImagesJob.perform_now(item.id)

      item.reload
      # Good image is rewritten
      assert_not_includes item.content, good_url
      assert_match %r{/rails/active_storage/blobs/}, item.content
      # Bad image preserves original URL
      assert_includes item.content, bad_url
      assert_equal 1, item.item_content.images.count
    end

    test "preserves original URL for failed downloads in rewritten HTML" do
      source = create_source!
      item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

      stub_request(:get, IMAGE_URL).to_return(status: 404)

      DownloadContentImagesJob.perform_now(item.id)

      item.reload
      # Content should not be rewritten since all downloads failed
      assert_includes item.content, IMAGE_URL
    end

    test "attaches downloaded images to item_content images" do
      source = create_source!
      item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

      stub_request(:get, IMAGE_URL)
        .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

      DownloadContentImagesJob.perform_now(item.id)

      item.reload
      assert item.item_content.images.attached?
      blob = item.item_content.images.first.blob
      assert_equal "image/png", blob.content_type
      assert_equal "photo.png", blob.filename.to_s
    end

    test "creates item_content if it does not exist yet" do
      source = create_source!
      item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

      assert_nil item.item_content

      stub_request(:get, IMAGE_URL)
        .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

      DownloadContentImagesJob.perform_now(item.id)

      item.reload
      assert_not_nil item.item_content
      assert item.item_content.persisted?
      assert item.item_content.images.attached?
    end

    private

    def create_item!(source:, content: nil)
      SourceMonitor::Item.create!(
        source: source,
        guid: SecureRandom.uuid,
        url: "https://example.com/#{SecureRandom.hex(6)}",
        title: "Test Article",
        content: content
      )
    end
  end
end
