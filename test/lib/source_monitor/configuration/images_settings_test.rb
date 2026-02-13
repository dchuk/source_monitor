# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class Configuration
    class ImagesSettingsTest < ActiveSupport::TestCase
      setup do
        SourceMonitor.reset_configuration!
        @settings = SourceMonitor.config.images
      end

      teardown do
        SourceMonitor.reset_configuration!
      end

      # -- Default values --

      test "download_to_active_storage defaults to false" do
        assert_equal false, @settings.download_to_active_storage
      end

      test "max_download_size defaults to 10 MB" do
        assert_equal 10 * 1024 * 1024, @settings.max_download_size
      end

      test "download_timeout defaults to 30 seconds" do
        assert_equal 30, @settings.download_timeout
      end

      test "allowed_content_types defaults to 5 image types" do
        expected = %w[image/jpeg image/png image/gif image/webp image/svg+xml]
        assert_equal expected, @settings.allowed_content_types
      end

      # -- Accessors --

      test "download_to_active_storage can be set" do
        @settings.download_to_active_storage = true
        assert_equal true, @settings.download_to_active_storage
      end

      test "max_download_size can be set" do
        @settings.max_download_size = 5 * 1024 * 1024
        assert_equal 5 * 1024 * 1024, @settings.max_download_size
      end

      test "download_timeout can be set" do
        @settings.download_timeout = 60
        assert_equal 60, @settings.download_timeout
      end

      test "allowed_content_types can be set" do
        @settings.allowed_content_types = %w[image/jpeg image/png]
        assert_equal %w[image/jpeg image/png], @settings.allowed_content_types
      end

      # -- reset! --

      test "reset! restores defaults after changes" do
        @settings.download_to_active_storage = true
        @settings.max_download_size = 1
        @settings.download_timeout = 1
        @settings.allowed_content_types = []

        @settings.reset!

        assert_equal false, @settings.download_to_active_storage
        assert_equal 10 * 1024 * 1024, @settings.max_download_size
        assert_equal 30, @settings.download_timeout
        assert_equal %w[image/jpeg image/png image/gif image/webp image/svg+xml], @settings.allowed_content_types
      end

      # -- download_enabled? --

      test "download_enabled? returns false by default" do
        assert_equal false, @settings.download_enabled?
      end

      test "download_enabled? returns true when download_to_active_storage is true" do
        @settings.download_to_active_storage = true
        assert_equal true, @settings.download_enabled?
      end

      test "download_enabled? returns false when download_to_active_storage is nil" do
        @settings.download_to_active_storage = nil
        assert_equal false, @settings.download_enabled?
      end

      # -- Integration --

      test "SourceMonitor.config.images returns ImagesSettings instance" do
        assert_instance_of ImagesSettings, SourceMonitor.config.images
      end

      test "SourceMonitor.reset_configuration! resets images settings" do
        SourceMonitor.config.images.download_to_active_storage = true
        SourceMonitor.config.images.max_download_size = 1

        SourceMonitor.reset_configuration!

        assert_equal false, SourceMonitor.config.images.download_to_active_storage
        assert_equal 10 * 1024 * 1024, SourceMonitor.config.images.max_download_size
      end

      test "allowed_content_types is a dup and does not mutate the default" do
        @settings.allowed_content_types << "image/avif"
        @settings.reset!

        assert_equal 5, @settings.allowed_content_types.size
        assert_not_includes @settings.allowed_content_types, "image/avif"
      end
    end
  end
end
