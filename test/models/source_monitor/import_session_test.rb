# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ImportSessionTest < ActiveSupport::TestCase
    fixtures :users

    test "creates with user and defaults" do
      import_session = ImportSession.create!(user_id: users(:admin).id, current_step: ImportSession.default_step)

      assert_equal ImportSession.default_step, import_session.current_step
      assert_equal users(:admin).id, import_session.user_id
      assert_equal({}, import_session.opml_file_metadata)
      assert_equal([], import_session.parsed_sources)
      assert_equal([], import_session.selected_source_ids)
      assert_equal({}, import_session.bulk_settings)
    end

    test "in_step scope returns sessions in given step" do
      upload_session = ImportSession.create!(user_id: users(:admin).id, current_step: "upload")
      preview_session = ImportSession.create!(user_id: users(:admin).id, current_step: "preview")

      results = ImportSession.in_step("upload")
      assert_includes results, upload_session
      assert_not_includes results, preview_session
    end

    test "step helpers navigate" do
      import_session = ImportSession.new(user_id: users(:admin).id, current_step: "preview")

      assert_equal "health_check", import_session.next_step
      assert_equal "upload", import_session.previous_step
    end
  end
end
