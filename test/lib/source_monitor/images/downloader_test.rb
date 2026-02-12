# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Images
    class DownloaderTest < ActiveSupport::TestCase
      TINY_PNG = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, # PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, # IHDR chunk
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, # 1x1 pixel
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, # 8-bit RGB
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, # IDAT chunk
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
        0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, # IEND chunk
        0x44, 0xAE, 0x42, 0x60, 0x82
      ].pack("C*").freeze

      IMAGE_URL = "https://cdn.example.com/photos/landscape.png"

      setup do
        SourceMonitor.reset_configuration!
      end

      test "downloads valid image and returns Result with io, filename, content_type, byte_size" do
        stub_request(:get, IMAGE_URL)
          .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

        result = Downloader.new(IMAGE_URL).call

        assert_instance_of Downloader::Result, result
        assert_equal "landscape.png", result.filename
        assert_equal "image/png", result.content_type
        assert_equal TINY_PNG.bytesize, result.byte_size
        assert_equal TINY_PNG, result.io.read
      end

      test "returns nil for HTTP 404 error" do
        stub_request(:get, IMAGE_URL).to_return(status: 404)

        assert_nil Downloader.new(IMAGE_URL).call
      end

      test "returns nil for HTTP 500 error" do
        stub_request(:get, IMAGE_URL).to_return(status: 500)

        assert_nil Downloader.new(IMAGE_URL).call
      end

      test "returns nil for disallowed content type" do
        stub_request(:get, IMAGE_URL)
          .to_return(body: "<html>not an image</html>", headers: { "Content-Type" => "text/html" })

        assert_nil Downloader.new(IMAGE_URL).call
      end

      test "returns nil for image exceeding max_download_size" do
        SourceMonitor.configure do |config|
          config.images.max_download_size = 10 # 10 bytes
        end

        stub_request(:get, IMAGE_URL)
          .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

        assert_nil Downloader.new(IMAGE_URL).call
      end

      test "returns nil for empty response body" do
        stub_request(:get, IMAGE_URL)
          .to_return(body: "", headers: { "Content-Type" => "image/png" })

        assert_nil Downloader.new(IMAGE_URL).call
      end

      test "returns nil for network timeout" do
        stub_request(:get, IMAGE_URL).to_timeout

        assert_nil Downloader.new(IMAGE_URL).call
      end

      test "derives filename from URL path when available" do
        stub_request(:get, "https://cdn.example.com/img/photo.jpg")
          .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/jpeg" })

        result = Downloader.new("https://cdn.example.com/img/photo.jpg").call

        assert_equal "photo.jpg", result.filename
      end

      test "generates random filename when URL has no extension" do
        stub_request(:get, "https://cdn.example.com/image")
          .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

        result = Downloader.new("https://cdn.example.com/image").call

        assert_match(/\Aimage-[a-f0-9]{16}\.png\z/, result.filename)
      end

      test "uses configured download_timeout" do
        SourceMonitor.configure do |config|
          config.images.download_timeout = 5
        end

        stub_request(:get, IMAGE_URL)
          .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

        result = Downloader.new(IMAGE_URL).call

        assert_not_nil result
      end

      test "uses configured allowed_content_types" do
        SourceMonitor.configure do |config|
          config.images.allowed_content_types = %w[image/webp]
        end

        stub_request(:get, IMAGE_URL)
          .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/png" })

        # PNG is not in the custom allowed list
        assert_nil Downloader.new(IMAGE_URL).call

        stub_request(:get, "https://cdn.example.com/photo.webp")
          .to_return(body: TINY_PNG, headers: { "Content-Type" => "image/webp" })

        result = Downloader.new("https://cdn.example.com/photo.webp").call
        assert_not_nil result
        assert_equal "image/webp", result.content_type
      end
    end
  end
end
