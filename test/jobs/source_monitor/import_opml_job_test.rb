# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ImportOpmlJobTest < ActiveJob::TestCase
    fixtures :users

    setup do
      @user = users(:admin)
      configure_authentication(@user, authorize: true)
    end

    test "delegates to OPMLImporter service" do
      session = SourceMonitor::ImportSession.create!(
        user_id: @user.id,
        current_step: "confirm",
        parsed_sources: [
          { "id" => "one", "feed_url" => "https://new-#{SecureRandom.hex(4)}.example.com/rss", "title" => "New" }
        ],
        selected_source_ids: %w[one],
        bulk_settings: { "fetch_interval_minutes" => 15 }
      )

      history = SourceMonitor::ImportHistory.create!(user_id: @user.id, bulk_settings: session.bulk_settings)

      importer_called = false
      fake_importer = Object.new
      fake_importer.define_singleton_method(:call) { importer_called = true }

      SourceMonitor::ImportSessions::OPMLImporter.stub(:new, ->(**_args) { fake_importer }) do
        SourceMonitor::ImportOpmlJob.perform_now(session.id, history.id)
      end

      assert importer_called, "expected OPMLImporter#call to be invoked"
    end

    test "silently skips when import_session not found" do
      history = SourceMonitor::ImportHistory.create!(user_id: @user.id)

      assert_nothing_raised do
        SourceMonitor::ImportOpmlJob.perform_now(-1, history.id)
      end
    end

    test "silently skips when import_history not found" do
      session = SourceMonitor::ImportSession.create!(
        user_id: @user.id,
        current_step: "confirm",
        parsed_sources: [],
        selected_source_ids: []
      )

      assert_nothing_raised do
        SourceMonitor::ImportOpmlJob.perform_now(session.id, -1)
      end
    end

    test "end-to-end import via job" do
      create_source!(feed_url: "https://dup.example.com/rss")

      session = SourceMonitor::ImportSession.create!(
        user_id: @user.id,
        current_step: "confirm",
        parsed_sources: [
          { "id" => "one", "feed_url" => "https://new-#{SecureRandom.hex(4)}.example.com/rss", "title" => "New", "status" => "valid" },
          { "id" => "dup", "feed_url" => "https://dup.example.com/rss", "title" => "Dup", "status" => "valid" },
          { "id" => "invalid", "feed_url" => nil, "title" => "Missing URL", "status" => "valid" }
        ],
        selected_source_ids: %w[one dup invalid],
        bulk_settings: { "fetch_interval_minutes" => 15, "scraper_adapter" => "readability" }
      )

      history = SourceMonitor::ImportHistory.create!(user_id: @user.id, bulk_settings: session.bulk_settings)

      perform_enqueued_jobs do
        SourceMonitor::ImportOpmlJob.perform_later(session.id, history.id)
      end

      history.reload

      assert_equal 1, history.imported_sources.size
      assert_equal 1, history.failed_sources.size
      assert_equal 1, history.skipped_duplicates.size
      assert history.completed_at.present?
      assert history.started_at.present?
    end

  end
end
