# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class DownloadContentImagesJobTest < ActiveJob::TestCase
    IMAGE_URL = "https://cdn.example.com/photo.png"

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

    setup do
      SourceMonitor.reset_configuration!
      SourceMonitor.configure do |config|
        config.images.download_to_active_storage = true
      end
    end

    test "delegates to Images::Processor" do
      source = create_source!
      item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

      processor_called = false
      fake_processor = Object.new
      fake_processor.define_singleton_method(:call) { processor_called = true }

      SourceMonitor::Images::Processor.stub(:new, ->(_item) { fake_processor }) do
        DownloadContentImagesJob.perform_now(item.id)
      end

      assert processor_called, "expected Images::Processor#call to be invoked"
    end

    test "silently skips when item not found" do
      assert_nothing_raised do
        DownloadContentImagesJob.perform_now(-1)
      end
    end

    test "end-to-end downloads images and rewrites content" do
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
  end
end
