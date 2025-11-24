# frozen_string_literal: true

require "test_helper"
require "cgi"

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

    test "upload parses opml, stores parsed sources, and advances to preview" do
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "upload")
      file = Rack::Test::UploadedFile.new(file_fixture("files/opml_with_valid_and_invalid.xml"), "text/xml")

      patch source_monitor.step_import_session_path(session, step: "upload"), params: {
        opml_file: file,
        import_session: { next_step: "preview" }
      }

      assert_redirected_to source_monitor.step_import_session_path(session, step: "preview")

      session.reload
      assert_equal "preview", session.current_step
      assert_equal "opml_with_valid_and_invalid.xml", session.opml_file_metadata["filename"]
      assert session.opml_file_metadata["uploaded_at"].present?

      assert_equal 3, session.parsed_sources.size
      valid, malformed = session.parsed_sources.partition { |entry| entry["status"] == "valid" }
      assert_equal 1, valid.size
      assert_equal "https://rubyflow.com/rss", valid.first["feed_url"]
      assert_equal 2, malformed.size
      assert_includes malformed.map { |entry| entry["error"] }, "Missing feed URL"
      assert_includes malformed.map { |entry| entry["error"] }, "Feed URL must be HTTP or HTTPS"
    end

    test "upload rejects invalid content type" do
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "upload")
      file = Rack::Test::UploadedFile.new(StringIO.new("not xml"), "text/plain", original_filename: "notes.txt")

      patch source_monitor.step_import_session_path(session, step: "upload"), params: {
        opml_file: file,
        import_session: { next_step: "preview" }
      }

      assert_response :unprocessable_entity
      session.reload
      assert_equal "upload", session.current_step
      assert_equal [], session.parsed_sources
      assert_includes @response.body, "Upload must be an OPML or XML file"
    end

    test "upload handles malformed xml" do
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "upload")
      file = Rack::Test::UploadedFile.new(file_fixture("files/opml_malformed.xml"), "text/xml")

      patch source_monitor.step_import_session_path(session, step: "upload"), params: {
        opml_file: file,
        import_session: { next_step: "preview" }
      }

      assert_response :unprocessable_entity
      session.reload
      assert_equal "upload", session.current_step
      assert_equal [], session.parsed_sources
      html = CGI.unescapeHTML(@response.body)
      assert_includes html, "We couldn't parse that OPML file"
    end

    test "upload blocks progression when no valid entries" do
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "upload")
      file = Rack::Test::UploadedFile.new(file_fixture("files/opml_no_valid_entries.xml"), "text/xml")

      patch source_monitor.step_import_session_path(session, step: "upload"), params: {
        opml_file: file,
        import_session: { next_step: "preview" }
      }

      assert_response :unprocessable_entity
      session.reload
      assert_equal "upload", session.current_step
      assert_equal 2, session.parsed_sources.size
      html = CGI.unescapeHTML(@response.body)
      assert_includes html, "We couldn't find any valid feeds"
    end

    test "scopes sessions to current user" do
      other_user = users(:viewer)
      session = SourceMonitor::ImportSession.create!(user_id: other_user.id, current_step: "upload")

      get source_monitor.step_import_session_path(session, step: "upload")

      assert_response :forbidden
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
