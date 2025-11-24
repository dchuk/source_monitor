# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ImportSessionsControllerTest < ActionDispatch::IntegrationTest
    fixtures :users

    setup do
      @admin = users(:admin)
      configure_authentication(@admin)
    end

    test "new creates session and redirects to first step" do
      assert_difference "SourceMonitor::ImportSession.count", 1 do
        get source_monitor.new_import_session_path
      end

      import_session = SourceMonitor::ImportSession.last
      assert_redirected_to source_monitor.step_import_session_path(import_session, step: "upload")
      assert_equal @admin.id, import_session.user_id
      assert_equal "upload", import_session.current_step
    end

    test "update saves upload metadata and advances step" do
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "upload")
      file = Rack::Test::UploadedFile.new(file_fixture("feeds/atom_sample.xml"), "text/xml")

      patch source_monitor.step_import_session_path(session, step: "upload"), params: {
        opml_file: file,
        import_session: { next_step: "preview" }
      }

      assert_redirected_to source_monitor.step_import_session_path(session, step: "preview")
      session.reload
      assert_equal "preview", session.current_step
      assert_equal "atom_sample.xml", session.opml_file_metadata["filename"]
    end

    test "destroy cancels session and redirects to sources" do
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "upload")

      assert_difference "SourceMonitor::ImportSession.count", -1 do
        delete source_monitor.import_session_path(session)
      end

      assert_redirected_to source_monitor.sources_path
    end

    test "sidebar marks active step" do
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "configure")

      get source_monitor.step_import_session_path(session, step: "configure")

      assert_response :success
      assert_includes @response.body, "aria-current=\"page\""
      assert_includes @response.body, "Import Wizard"
      assert_includes @response.body, "confirm-navigation"
    end

    private

    def configure_authentication(user)
      SourceMonitor.configure do |config|
        config.authentication.current_user_method = :current_user
        config.authentication.user_signed_in_method = :user_signed_in?

        config.authentication.authenticate_with lambda { |controller|
          controller.singleton_class.define_method(:current_user) { user }
          controller.singleton_class.define_method(:user_signed_in?) { user.present? }
        }

        config.authentication.authorize_with lambda { |controller|
          raise ActionController::RoutingError, "Not Found" unless user&.admin?
        }
      end
    end
  end
end
