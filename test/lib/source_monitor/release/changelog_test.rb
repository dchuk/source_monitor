# frozen_string_literal: true

require "test_helper"
require "source_monitor/release/changelog"

module SourceMonitor
  module Release
    class ChangelogTest < ActiveSupport::TestCase
      def setup
        @changelog_file = Tempfile.new([ "changelog", ".md" ])
        @changelog_file.write(<<~MARKDOWN)
          # Changelog

          ## Release Checklist

          1. Ensure quality gates pass
          2. Build the gem

          ## 2025-10-14

          - Latest release notes here.

          ### Upgrade Notes

          1. Do a thing.

          ## 2025-09-18

          - Older release entry.
        MARKDOWN
        @changelog_file.flush
      end

      def teardown
        @changelog_file.close
        @changelog_file.unlink
      end

      def test_latest_entry_returns_most_recent_release_section
        changelog = Changelog.new(path: @changelog_file.path)

        expected = <<~MARKDOWN.strip
          ## 2025-10-14
          - Latest release notes here.

          ### Upgrade Notes

          1. Do a thing.
        MARKDOWN

        assert_equal expected, changelog.latest_entry
      end

      def test_annotation_for_version_wraps_entry_with_release_header
        changelog = Changelog.new(path: @changelog_file.path)

        expected = <<~MARKDOWN.strip
          SourceMonitor v1.2.3

          ## 2025-10-14
          - Latest release notes here.

          ### Upgrade Notes

          1. Do a thing.
        MARKDOWN

        assert_equal expected, changelog.annotation_for("1.2.3")
      end
    end
  end
end
