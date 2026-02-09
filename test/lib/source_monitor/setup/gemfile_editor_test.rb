# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module SourceMonitor
  module Setup
    class GemfileEditorTest < ActiveSupport::TestCase
      test "appends source_monitor gem when missing" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "Gemfile")
          File.write(path, "source 'https://rubygems.org'\n")

          editor = GemfileEditor.new(path:)

          assert editor.ensure_entry
          assert_includes File.read(path), "gem \"source_monitor\""
          refute editor.ensure_entry, "should be idempotent"
        end
      end

      test "returns false when gemfile missing" do
        editor = GemfileEditor.new(path: "/tmp/does-not-exist")
        refute editor.ensure_entry
      end
    end
  end
end
