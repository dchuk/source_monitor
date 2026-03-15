# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Images
    class ProcessorTest < ActiveSupport::TestCase
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

      test "downloads images and rewrites HTML with blob URLs" do
        source = create_source!
        item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

        stub_request(:get, IMAGE_URL)
          .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

        Processor.new(item).call

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

        Processor.new(item).call

        item.reload
        assert_includes item.content, IMAGE_URL
      end

      test "skips when item content is blank" do
        source = create_source!
        item = create_item!(source: source, content: nil)

        assert_nothing_raised do
          Processor.new(item).call
        end
      end

      test "skips when images already attached (idempotency)" do
        source = create_source!
        item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

        stub_request(:get, IMAGE_URL)
          .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

        Processor.new(item).call
        item.reload
        first_content = item.content

        Processor.new(item).call
        item.reload
        assert_equal first_content, item.content
        assert_equal 1, item.item_content.images.count
      end

      test "skips when no image URLs found" do
        source = create_source!
        item = create_item!(source: source, content: "<p>No images here</p>")

        Processor.new(item).call

        item.reload
        assert_equal "<p>No images here</p>", item.content
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

        Processor.new(item).call

        item.reload
        assert_not_includes item.content, good_url
        assert_match %r{/rails/active_storage/blobs/}, item.content
        assert_includes item.content, bad_url
        assert_equal 1, item.item_content.images.count
      end

      test "re-raises transient errors" do
        source = create_source!
        item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

        SourceMonitor::Images::Downloader.stub(:new, ->(_url, **_opts) {
          obj = Object.new
          def obj.call
            raise Faraday::TimeoutError, "connection timed out"
          end
          obj
        }) do
          assert_raises(Faraday::TimeoutError) do
            Processor.new(item).call
          end
        end
      end

      test "re-raises ActiveRecord::Deadlocked" do
        source = create_source!
        item = create_item!(source: source, content: %(<p><img src="#{IMAGE_URL}"></p>))

        SourceMonitor::Images::Downloader.stub(:new, ->(_url, **_opts) {
          obj = Object.new
          def obj.call
            raise ActiveRecord::Deadlocked, "PG::TRDeadlockDetected"
          end
          obj
        }) do
          assert_raises(ActiveRecord::Deadlocked) do
            Processor.new(item).call
          end
        end
      end

      test "creates item_content if it does not exist" do
        source = create_source!
        item = create_item!(source: source, content: nil)
        item.update_columns(content: %(<p><img src="#{IMAGE_URL}"></p>))

        assert_nil item.reload.item_content

        stub_request(:get, IMAGE_URL)
          .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

        Processor.new(item).call

        item.reload
        assert_not_nil item.item_content
        assert item.item_content.persisted?
        assert item.item_content.images.attached?
      end
    end
  end
end
