# frozen_string_literal: true

require "test_helper"
require_relative "support/system_test_helpers"

module SourceMonitor
  class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]
    include ActionCable::TestHelper
    include Turbo::Broadcastable::TestHelper
    include SystemTestHelpers

    # Centralize Capybara wait time so individual assertions don't need
    # explicit `wait: 5` for standard async operations.
    Capybara.default_max_wait_time = 5

    setup do
      SourceMonitor.reset_configuration!
      SourceMonitor::Jobs::Visibility.reset!
      SourceMonitor::Jobs::Visibility.setup!
    end

    teardown do
      SourceMonitor.reset_configuration!
      SourceMonitor::Jobs::Visibility.reset!
      clean_test_tmp_files
    end

    private

    # Save a screenshot when a test fails (delegates to Capybara's built-in
    # mechanism when available).
    def after_teardown
      take_failed_screenshot if respond_to?(:take_failed_screenshot)
      super
    end

    # Remove stale artifacts from test/tmp/ that are older than 1 hour.
    # This prevents unbounded disk growth from generated test files.
    def clean_test_tmp_files
      tmp_dir = File.expand_path("tmp", __dir__)
      return unless Dir.exist?(tmp_dir)

      cutoff = Time.now - 3600
      Dir.glob(File.join(tmp_dir, "**", "*")).each do |path|
        next unless File.file?(path)
        next unless File.mtime(path) < cutoff

        FileUtils.rm_f(path)
      end
    end
  end
end
