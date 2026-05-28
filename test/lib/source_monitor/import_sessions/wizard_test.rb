# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module ImportSessions
    class WizardTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      fixtures :users

      setup do
        clean_source_monitor_tables!
        @user = users(:admin)
      end

      test "upload valid OPML persists metadata parsed sources and advances" do
        import_session = build_session
        file = uploaded_file("files/opml_with_valid_and_invalid.xml")

        result = wizard(import_session, params: { opml_file: file, import_session: { next_step: "preview" } }).handle_upload

        assert_equal :success, result.status
        assert_equal "preview", result.current_step

        import_session.reload
        assert_equal "preview", import_session.current_step
        assert_equal "opml_with_valid_and_invalid.xml", import_session.opml_file_metadata["filename"]
        assert import_session.opml_file_metadata["uploaded_at"].present?
        assert_equal 3, import_session.parsed_sources.size
        assert_equal 1, import_session.parsed_sources.count { |entry| entry["status"] == "valid" }
        assert_equal 2, import_session.parsed_sources.count { |entry| entry["status"] == "malformed" }
      end

      test "upload invalid content type returns errors without advancing" do
        import_session = build_session
        file = Rack::Test::UploadedFile.new(StringIO.new("not xml"), "text/plain", original_filename: "notes.txt")

        result = wizard(import_session, params: { opml_file: file, import_session: { next_step: "preview" } }).handle_upload

        assert_equal :invalid, result.status
        assert_includes result.errors, "Upload must be an OPML or XML file."
        assert_equal "upload", import_session.reload.current_step
        assert_equal [], import_session.parsed_sources
      end

      test "upload OPML with no valid entries persists parsed errors and stays on upload" do
        import_session = build_session
        file = uploaded_file("files/opml_no_valid_entries.xml")

        result = wizard(import_session, params: { opml_file: file, import_session: { next_step: "preview" } }).handle_upload

        assert_equal :invalid, result.status
        assert_includes result.errors.first, "We couldn't find any valid feeds"
        import_session.reload
        assert_equal "upload", import_session.current_step
        assert_equal 2, import_session.parsed_sources.size
        assert_equal "opml_no_valid_entries.xml", import_session.opml_file_metadata["filename"]
      end

      test "preview context is read-only when no selection exists" do
        import_session = build_session(
          current_step: "preview",
          parsed_sources: selectable_parsed_sources,
          selected_source_ids: []
        )

        context = wizard(import_session, current_step: "preview").preview_context

        assert_equal [], import_session.reload.selected_source_ids
        assert_equal [ false, false ], context.preview_entries.map { |entry| entry[:selected] }
      end

      test "preview context with default selection annotates duplicates and persists selectable entries" do
        existing = create_source!(feed_url: "https://dup.example.com/feed.xml")
        import_session = build_session(
          current_step: "preview",
          parsed_sources: [
            { "id" => "one", "feed_url" => existing.feed_url, "title" => "Existing", "status" => "valid" },
            { "id" => "two", "feed_url" => "https://new.example.com/rss", "title" => "New", "status" => "valid" },
            { "id" => "three", "feed_url" => nil, "status" => "malformed", "error" => "Missing feed URL" }
          ],
          selected_source_ids: []
        )

        context = wizard(import_session, current_step: "preview").preview_context_with_default_selection

        import_session.reload
        assert_equal [ "two" ], import_session.selected_source_ids
        assert_equal [ true, false, false ], context.preview_entries.map { |entry| entry[:duplicate] }
        assert_equal [ false, true, false ], context.preview_entries.map { |entry| entry[:selectable] }
        assert_equal [ false, true, false ], context.preview_entries.map { |entry| entry[:selected] }
      end

      test "preview select all and select none persist selected IDs with true strings" do
        import_session = build_session(current_step: "preview", parsed_sources: selectable_parsed_sources)

        select_all = wizard(import_session, current_step: "preview", params: { import_session: { select_all: "true", next_step: "preview" } }).handle_preview
        assert_equal :success, select_all.status
        assert_equal [ "one", "two" ], import_session.reload.selected_source_ids.sort

        select_none = wizard(import_session, current_step: "preview", params: { import_session: { select_none: "true", next_step: "preview" } }).handle_preview
        assert_equal :success, select_none.status
        assert_equal [], import_session.reload.selected_source_ids
      end

      test "preview select all and select none persist selected IDs with checkbox payloads" do
        import_session = build_session(current_step: "preview", parsed_sources: selectable_parsed_sources)

        select_all = wizard(import_session, current_step: "preview", params: { import_session: { select_all: "1", next_step: "preview" } }).handle_preview
        assert_equal :success, select_all.status
        assert_equal [ "one", "two" ], import_session.reload.selected_source_ids.sort

        select_none = wizard(import_session, current_step: "preview", params: { import_session: { select_none: "1", next_step: "preview" } }).handle_preview
        assert_equal :success, select_none.status
        assert_equal [], import_session.reload.selected_source_ids
      end

      test "preview blocks advancing with empty selection" do
        import_session = build_session(current_step: "preview", parsed_sources: selectable_parsed_sources)

        result = wizard(import_session, current_step: "preview", params: { import_session: { selected_source_ids: [], next_step: "health_check" } }).handle_preview

        assert result.blocked?
        assert_equal "Select at least one new source to continue.", result.selection_error
        assert_equal "preview", import_session.reload.current_step
      end

      test "health check context starts checks with injected timestamp and enqueues jobs" do
        import_session = build_session(
          current_step: "health_check",
          parsed_sources: selectable_parsed_sources,
          selected_source_ids: [ "one", "two" ]
        )
        now = Time.zone.parse("2026-05-28 12:00:00 UTC")

        context = nil
        assert_enqueued_jobs 2, only: SourceMonitor::ImportSessionHealthCheckJob do
          context = wizard(import_session, current_step: "health_check", now: now).health_check_context
        end

        import_session.reload
        assert import_session.health_checks_active?
        assert_equal %w[one two], import_session.health_check_target_ids
        assert_in_delta now, import_session.health_check_started_at, 1.second
        assert_equal %w[pending pending], import_session.parsed_sources.map { |entry| entry["health_status"] }
        assert_equal %w[one two], context.health_check_target_ids
        assert_equal({ completed: 0, total: 2, pending: 2, active: true, done: false }, context.health_progress)
      end

      test "health check context does not enqueue duplicate jobs for unchanged targets" do
        import_session = build_session(
          current_step: "health_check",
          parsed_sources: selectable_parsed_sources,
          selected_source_ids: [ "one" ],
          health_checks_active: true,
          health_check_target_ids: [ "one" ]
        )

        assert_no_enqueued_jobs only: SourceMonitor::ImportSessionHealthCheckJob do
          wizard(import_session, current_step: "health_check").health_check_context
        end

        assert_equal [ "one" ], import_session.reload.health_check_target_ids
      end

      test "health check handles select all and select none true strings against targets" do
        import_session = build_session(
          current_step: "health_check",
          parsed_sources: selectable_parsed_sources,
          selected_source_ids: [ "one" ],
          health_checks_active: true,
          health_check_target_ids: [ "one", "two" ]
        )

        select_all = wizard(import_session, current_step: "health_check", params: { import_session: { select_all: "true", next_step: "health_check" } }).handle_health_check
        assert_equal :success, select_all.status
        assert_equal %w[one two], import_session.reload.selected_source_ids.sort

        select_none = wizard(import_session, current_step: "health_check", params: { import_session: { select_none: "true", next_step: "health_check" } }).handle_health_check
        assert_equal :success, select_none.status
        assert_equal [], import_session.reload.selected_source_ids
      end

      test "health check handles select all and select none checkbox payloads against targets" do
        import_session = build_session(
          current_step: "health_check",
          parsed_sources: selectable_parsed_sources,
          selected_source_ids: [ "one" ],
          health_checks_active: true,
          health_check_target_ids: [ "one", "two" ]
        )

        select_all = wizard(import_session, current_step: "health_check", params: { import_session: { select_all: "1", next_step: "health_check" } }).handle_health_check
        assert_equal :success, select_all.status
        assert_equal %w[one two], import_session.reload.selected_source_ids.sort

        select_none = wizard(import_session, current_step: "health_check", params: { import_session: { select_none: "1", next_step: "health_check" } }).handle_health_check
        assert_equal :success, select_none.status
        assert_equal [], import_session.reload.selected_source_ids
      end

      test "health check blocks advancing with empty selection and deactivates checks with injected timestamp" do
        import_session = build_session(
          current_step: "health_check",
          parsed_sources: selectable_parsed_sources,
          selected_source_ids: [],
          health_checks_active: true,
          health_check_target_ids: [ "one" ]
        )
        now = Time.zone.parse("2026-05-28 13:00:00 UTC")

        result = wizard(import_session, current_step: "health_check", params: { import_session: { selected_source_ids: [], next_step: "configure" } }, now: now).handle_health_check

        assert result.blocked?
        assert_equal "Select at least one source to continue.", result.selection_error
        import_session.reload
        assert_equal "health_check", import_session.current_step
        assert_not import_session.health_checks_active?
        assert_in_delta now, import_session.health_check_completed_at, 1.second
      end

      test "health check context reports completed progress and selected entries" do
        import_session = build_session(
          current_step: "health_check",
          parsed_sources: [
            { "id" => "one", "feed_url" => "https://new.example.com/rss", "status" => "valid", "health_status" => "working" },
            { "id" => "two", "feed_url" => "https://another.example.com/rss", "status" => "valid", "health_status" => "pending" }
          ],
          selected_source_ids: [ "one", "two" ],
          health_checks_active: true,
          health_check_target_ids: [ "one", "two" ]
        )

        context = wizard(import_session, current_step: "health_check").health_check_context

        assert_equal [ true, true ], context.health_check_entries.map { |entry| entry[:selected] }
        assert_equal({ completed: 1, total: 2, pending: 1, active: true, done: false }, context.health_progress)
      end

      test "confirm context returns selected entries and bulk settings" do
        import_session = build_session(
          current_step: "confirm",
          parsed_sources: selectable_parsed_sources,
          selected_source_ids: [ "one" ],
          bulk_settings: { "fetch_interval_minutes" => 30 }
        )

        context = wizard(import_session, current_step: "confirm").confirm_context

        assert_equal [ "one" ], context.selected_source_ids
        assert_equal [ "one" ], context.selected_entries.map { |entry| entry[:id] }
        assert_equal({ "fetch_interval_minutes" => 30 }, context.bulk_settings)
      end

      test "confirm blocks when selected entries are empty" do
        import_session = build_session(current_step: "confirm", parsed_sources: [], selected_source_ids: [])

        result = nil
        assert_no_enqueued_jobs only: SourceMonitor::ImportOpmlJob do
          result = wizard(import_session, current_step: "confirm").handle_confirm
        end

        assert result.blocked?
        assert_equal "Select at least one source to import.", result.selection_error
        assert_equal 0, SourceMonitor::ImportHistory.count
      end

      test "confirm creates import history and enqueues import job" do
        import_session = build_session(
          current_step: "confirm",
          parsed_sources: selectable_parsed_sources,
          selected_source_ids: [ "one", "two" ],
          bulk_settings: { "fetch_interval_minutes" => 45 }
        )

        assert_difference "SourceMonitor::ImportHistory.count", 1 do
          assert_enqueued_with(job: SourceMonitor::ImportOpmlJob) do
            result = wizard(import_session, current_step: "confirm").handle_confirm

            assert_equal :success, result.status
            assert_equal "Import started for 2 sources.", result.message
            assert_equal [ "one", "two" ], result.selected_entries.map { |entry| entry[:id] }
          end
        end

        history = SourceMonitor::ImportHistory.order(:created_at).last
        assert_equal @user.id, history.user_id
        assert_equal({ "fetch_interval_minutes" => 45 }, history.bulk_settings)
      end

      private

      def build_session(attributes = {})
        SourceMonitor::ImportSession.create!(
          {
            user_id: @user.id,
            current_step: "upload"
          }.merge(attributes)
        )
      end

      def wizard(import_session, params: {}, current_step: import_session.current_step, now: Time.current)
        SourceMonitor::ImportSessions::Wizard.new(
          import_session: import_session,
          params: ActionController::Parameters.new(params),
          current_step: current_step,
          now: now
        )
      end

      def uploaded_file(fixture)
        Rack::Test::UploadedFile.new(file_fixture(fixture), "text/xml")
      end

      def selectable_parsed_sources
        [
          { "id" => "one", "feed_url" => "https://new.example.com/rss", "status" => "valid" },
          { "id" => "two", "feed_url" => "https://another.example.com/rss", "status" => "valid" }
        ]
      end
    end
  end
end
