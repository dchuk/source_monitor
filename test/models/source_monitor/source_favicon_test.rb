# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class SourceFaviconTest < ActiveSupport::TestCase
    setup do
      SourceMonitor.reset_configuration!
    end

    test "Source responds to favicon when ActiveStorage is defined" do
      source = create_source!
      assert_respond_to source, :favicon
    end

    test "source can have a favicon attached" do
      source = create_source!

      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("fake-icon-data"),
        filename: "favicon.ico",
        content_type: "image/x-icon"
      )
      source.favicon.attach(blob)

      assert source.favicon.attached?
    end

    test "source creation works without favicon" do
      source = create_source!(name: "No Favicon Source")

      assert source.persisted?
      assert_not source.favicon.attached?
    end
  end
end
