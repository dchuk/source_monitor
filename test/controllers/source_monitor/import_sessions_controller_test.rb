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

    test "preview shows duplicates and disables selection" do
      existing = create_source!(feed_url: "https://dup.example.com/feed.xml")
      parsed = [
        { "id" => "one", "feed_url" => existing.feed_url, "title" => "Existing", "status" => "valid" },
        { "id" => "two", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" },
        { "id" => "three", "feed_url" => nil, "status" => "malformed", "error" => "Missing feed URL" }
      ]
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "preview", parsed_sources: parsed)

      get source_monitor.step_import_session_path(session, step: "preview")

      assert_response :success
      assert_includes @response.body, "Already Imported"
      assert_includes @response.body, existing.feed_url
      assert_includes @response.body, "Parse error"
      assert_includes @response.body, "New"
    end

    test "preview defaults to selecting all selectable entries" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" },
        { "id" => "two", "feed_url" => "https://dup.example.com/rss", "title" => "Dup", "status" => "valid" }
      ]
      create_source!(feed_url: "https://dup.example.com/rss")
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "preview", parsed_sources: parsed, selected_source_ids: [])

      get source_monitor.step_import_session_path(session, step: "preview")

      session.reload
      assert_equal [ "one" ], session.selected_source_ids
      assert_includes @response.body, "checked\""
    end

    test "preview select all and select none controls" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "status" => "valid" },
        { "id" => "two", "feed_url" => "https://another.example.com/rss", "status" => "valid" }
      ]
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "preview", parsed_sources: parsed, selected_source_ids: [])

      patch source_monitor.step_import_session_path(session, step: "preview"), params: {
        import_session: { select_all: "true", next_step: "preview" }
      }

      session.reload
      assert_equal [ "one", "two" ], session.selected_source_ids.sort

      patch source_monitor.step_import_session_path(session, step: "preview"), params: {
        import_session: { select_none: "true", next_step: "preview" }
      }

      session.reload
      assert_equal [], session.selected_source_ids
    end

    test "preview filter existing shows only duplicates" do
      existing = create_source!(feed_url: "https://dup.example.com/feed.xml")
      parsed = [
        { "id" => "one", "feed_url" => existing.feed_url, "title" => "Existing", "status" => "valid" },
        { "id" => "two", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" }
      ]
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "preview", parsed_sources: parsed)

      get source_monitor.step_import_session_path(session, step: "preview", filter: "existing")

      assert_response :success
      assert_includes @response.body, existing.feed_url
      refute_includes @response.body, "https://new.example.com/rss"
    end

    test "preview selection persists and advances when valid" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" }
      ]
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "preview", parsed_sources: parsed)

      patch source_monitor.step_import_session_path(session, step: "preview"), params: {
        import_session: { selected_source_ids: [ "one" ], next_step: "health_check" }
      }

      assert_redirected_to source_monitor.step_import_session_path(session, step: "health_check")
      session.reload
      assert_equal [ "one" ], session.selected_source_ids
      assert_equal "health_check", session.current_step
    end

    test "health check enqueues jobs and marks entries pending" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" },
        { "id" => "two", "feed_url" => "https://another.example.com/rss", "title" => "Another", "status" => "valid" }
      ]
      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "preview",
        parsed_sources: parsed,
        selected_source_ids: [ "one", "two" ]
      )

      assert_enqueued_jobs 2, only: SourceMonitor::ImportSessionHealthCheckJob do
        patch source_monitor.step_import_session_path(session, step: "preview"), params: {
          import_session: { selected_source_ids: [ "one", "two" ], next_step: "health_check" }
        }
      end

      session.reload
      assert session.health_checks_active?
      assert_equal %w[one two], session.health_check_target_ids
      assert_equal %w[pending pending], session.parsed_sources.map { |entry| entry["health_status"] }
    end

    test "health check blocks advance when no selections remain" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid", "health_status" => "unhealthy" }
      ]
      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "health_check",
        parsed_sources: parsed,
        selected_source_ids: [],
        health_checks_active: true,
        health_check_target_ids: [ "one" ]
      )

      patch source_monitor.step_import_session_path(session, step: "health_check"), params: {
        import_session: { selected_source_ids: [], next_step: "configure" }
      }

      assert_response :unprocessable_entity
      session.reload
      assert_equal "health_check", session.current_step
      refute session.health_checks_active?
    end

    test "preview blocks advance when selection empty" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" }
      ]
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "preview", parsed_sources: parsed)

      patch source_monitor.step_import_session_path(session, step: "preview"), params: {
        import_session: { selected_source_ids: [], next_step: "health_check" }
      }

      assert_response :unprocessable_entity
      session.reload
      assert_equal [], session.selected_source_ids
      assert_equal "preview", session.current_step
      html = CGI.unescapeHTML(@response.body)
      assert_includes html, "Select at least one new source"
    end

    test "configure persists bulk settings and advances to confirm" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" }
      ]

      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "configure",
        parsed_sources: parsed,
        selected_source_ids: [ "one" ],
        bulk_settings: {}
      )

      patch source_monitor.step_import_session_path(session, step: "configure"), params: {
        import_session: { next_step: "confirm" },
        source: {
          fetch_interval_minutes: 15,
          active: "1",
          auto_scrape: "1",
          scraping_enabled: "1",
          scraper_adapter: "readability",
          items_retention_days: 30
        }
      }

      assert_redirected_to source_monitor.step_import_session_path(session, step: "confirm")

      session.reload
      assert_equal "confirm", session.current_step
      assert_equal 15, session.bulk_settings["fetch_interval_minutes"]
      assert_equal true, session.bulk_settings["scraping_enabled"]
      assert_equal 30, session.bulk_settings["items_retention_days"]
    end

    test "configure blocks advance when settings invalid" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" }
      ]

      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "configure",
        parsed_sources: parsed,
        selected_source_ids: [ "one" ],
        bulk_settings: {}
      )

      patch source_monitor.step_import_session_path(session, step: "configure"), params: {
        import_session: { next_step: "confirm" },
        source: {
          fetch_interval_minutes: 0,
          scraper_adapter: "readability"
        }
      }

      assert_response :unprocessable_entity
      session.reload
      assert_equal "configure", session.current_step
      html = CGI.unescapeHTML(@response.body)
      assert_includes html, "Fetch interval minutes must be greater than 0"
    end

    test "confirm enqueues import job and records import history" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" }
      ]

      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "confirm",
        parsed_sources: parsed,
        selected_source_ids: [ "one" ],
        bulk_settings: { "fetch_interval_minutes" => 30 }
      )

      assert_enqueued_with(job: SourceMonitor::ImportOpmlJob) do
        patch source_monitor.step_import_session_path(session, step: "confirm"), params: {
          import_session: { next_step: "confirm" }
        }
      end

      assert_redirected_to source_monitor.sources_path

      history = SourceMonitor::ImportHistory.order(:created_at).last
      assert_equal @admin.id, history.user_id
      assert_equal session.bulk_settings, history.bulk_settings
    end

    test "confirm blocks progression when no selections remain" do
      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "confirm",
        parsed_sources: [],
        selected_source_ids: []
      )

      patch source_monitor.step_import_session_path(session, step: "confirm"), params: {
        import_session: { next_step: "confirm" }
      }

      assert_response :unprocessable_entity
      assert_includes @response.body, "Select at least one source"
    end

    test "confirm turbo stream renders redirect" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" }
      ]

      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "confirm",
        parsed_sources: parsed,
        selected_source_ids: [ "one" ],
        bulk_settings: {}
      )

      patch source_monitor.step_import_session_path(session, step: "confirm"), params: {
        import_session: { next_step: "confirm" }
      }, as: :turbo_stream

      assert_response :success
      assert_includes @response.body, "turbo-stream"
      assert_includes @response.body, "redirect"
    end

    test "show updates persisted step when visiting a different step" do
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "upload", parsed_sources: [])

      get source_monitor.step_import_session_path(session, step: "health_check", page: { bad: :value })

      session.reload
      assert_equal "health_check", session.current_step
    end

    test "health check advance deactivates checks and redirects" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid", "health_status" => "healthy" }
      ]

      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "health_check",
        parsed_sources: parsed,
        selected_source_ids: [ "one" ],
        health_checks_active: true,
        health_check_target_ids: [ "one" ]
      )

      patch source_monitor.step_import_session_path(session, step: "health_check"), params: {
        import_session: { selected_source_ids: [ "one" ], next_step: "configure" }
      }

      session.reload
      refute session.health_checks_active?
      assert_redirected_to source_monitor.step_import_session_path(session, step: "configure")
    end

    test "health check selection honors select all" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid", "health_status" => "pending" },
        { "id" => "two", "feed_url" => "https://another.example.com/rss", "title" => "Another", "status" => "valid", "health_status" => "pending" }
      ]

      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "health_check",
        parsed_sources: parsed,
        selected_source_ids: [ "one" ],
        health_checks_active: true,
        health_check_target_ids: [ "one", "two" ]
      )

      patch source_monitor.step_import_session_path(session, step: "health_check"), params: {
        import_session: { select_all: "true", next_step: "health_check" }
      }

      session.reload
      assert_equal %w[one two], session.selected_source_ids.sort
    end

    test "preview filter new path returns selectable entries" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" },
        { "id" => "two", "feed_url" => "https://dup.example.com/rss", "title" => "Dup", "status" => "valid" }
      ]
      create_source!(feed_url: "https://dup.example.com/rss")
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "preview", parsed_sources: parsed)

      get source_monitor.step_import_session_path(session, step: "preview", filter: "new")

      assert_response :success
      refute_includes @response.body, "https://dup.example.com/rss"
      assert_includes @response.body, "https://new.example.com/rss"
    end

    test "confirm show renders summary" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" }
      ]

      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "confirm",
        parsed_sources: parsed,
        selected_source_ids: [ "one" ],
        bulk_settings: { "fetch_interval_minutes" => 30 }
      )

      get source_monitor.step_import_session_path(session, step: "confirm")

      assert_response :success
      assert_includes @response.body, "Review &amp; confirm"
      assert_includes @response.body, "Fetch interval minutes"
    end

    test "update uses fallback branch when step unknown" do
      session = SourceMonitor::ImportSession.create!(user_id: @admin.id, current_step: "upload")
      session.update_column(:current_step, "done")

      patch source_monitor.step_import_session_path(session, step: "done"), params: {
        import_session: { next_step: "confirm" }
      }

      session.reload
      assert_equal "confirm", session.current_step
      assert_redirected_to source_monitor.step_import_session_path(session, step: "confirm")
    end

    test "start health checks returns existing targets when unchanged" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid", "health_status" => "pending" }
      ]

      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "health_check",
        parsed_sources: parsed,
        selected_source_ids: [ "one" ],
        health_checks_active: true,
        health_check_target_ids: [ "one" ]
      )

      assert_no_enqueued_jobs only: SourceMonitor::ImportSessionHealthCheckJob do
        get source_monitor.step_import_session_path(session, step: "health_check")
      end

      assert_response :success
      session.reload
      assert_equal [ "one" ], session.health_check_target_ids
    end

    test "configure form reuses saved settings" do
      parsed = [
        { "id" => "one", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" }
      ]

      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "configure",
        parsed_sources: parsed,
        selected_source_ids: [ "one" ],
        bulk_settings: { "fetch_interval_minutes" => 45, "scraping_enabled" => true }
      )

      get source_monitor.step_import_session_path(session, step: "configure")

      assert_response :success
      assert_includes @response.body, "value=\"45\""
      assert_includes @response.body, "scraping_enabled"
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
