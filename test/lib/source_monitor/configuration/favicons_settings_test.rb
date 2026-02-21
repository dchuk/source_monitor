# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class Configuration
    class FaviconsSettingsTest < ActiveSupport::TestCase
      setup do
        SourceMonitor.reset_configuration!
        @settings = SourceMonitor.config.favicons
      end

      teardown do
        SourceMonitor.reset_configuration!
      end

      # -- Default values --

      test "enabled defaults to true" do
        assert_equal true, @settings.enabled
      end

      test "fetch_timeout defaults to 5 seconds" do
        assert_equal 5, @settings.fetch_timeout
      end

      test "max_download_size defaults to 1 MB" do
        assert_equal 1 * 1024 * 1024, @settings.max_download_size
      end

      test "retry_cooldown_days defaults to 7" do
        assert_equal 7, @settings.retry_cooldown_days
      end

      test "allowed_content_types includes image/x-icon" do
        assert_includes @settings.allowed_content_types, "image/x-icon"
      end

      test "allowed_content_types includes all expected types" do
        expected = %w[
          image/x-icon
          image/vnd.microsoft.icon
          image/png
          image/jpeg
          image/gif
          image/svg+xml
          image/webp
        ]
        assert_equal expected, @settings.allowed_content_types
      end

      # -- reset! --

      test "reset! restores defaults after mutation" do
        @settings.enabled = false
        @settings.fetch_timeout = 30
        @settings.max_download_size = 999
        @settings.retry_cooldown_days = 1
        @settings.allowed_content_types = []

        @settings.reset!

        assert_equal true, @settings.enabled
        assert_equal 5, @settings.fetch_timeout
        assert_equal 1 * 1024 * 1024, @settings.max_download_size
        assert_equal 7, @settings.retry_cooldown_days
        assert_equal 7, @settings.allowed_content_types.size
      end

      # -- enabled? --

      test "enabled? returns false when enabled is false" do
        @settings.enabled = false
        assert_equal false, @settings.enabled?
      end

      test "enabled? returns true when ActiveStorage is defined and enabled is true" do
        @settings.enabled = true
        # ActiveStorage is defined in the test dummy app
        assert_equal true, @settings.enabled?
      end

      test "enabled? returns false when enabled is nil" do
        @settings.enabled = nil
        assert_equal false, @settings.enabled?
      end

      # -- Integration --

      test "SourceMonitor.config.favicons returns FaviconsSettings instance" do
        assert_instance_of FaviconsSettings, SourceMonitor.config.favicons
      end

      test "SourceMonitor.reset_configuration! resets favicons settings" do
        SourceMonitor.config.favicons.enabled = false
        SourceMonitor.config.favicons.fetch_timeout = 99

        SourceMonitor.reset_configuration!

        assert_equal true, SourceMonitor.config.favicons.enabled
        assert_equal 5, SourceMonitor.config.favicons.fetch_timeout
      end

      test "allowed_content_types is a dup and does not mutate the default" do
        @settings.allowed_content_types << "image/avif"
        @settings.reset!

        assert_equal 7, @settings.allowed_content_types.size
        assert_not_includes @settings.allowed_content_types, "image/avif"
      end
    end
  end
end
