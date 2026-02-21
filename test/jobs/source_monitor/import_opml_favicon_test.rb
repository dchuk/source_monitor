# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ImportOpmlFaviconTest < ActiveJob::TestCase
    fixtures :users

    setup do
      SourceMonitor.reset_configuration!
      @user = users(:admin)
      configure_authentication(@user)
    end

    test "OPML import enqueues FaviconFetchJob for sources with website_url" do
      session = create_import_session(
        parsed_sources: [
          { "id" => "s1", "feed_url" => "https://one.example.com/feed.xml", "title" => "One", "website_url" => "https://one.example.com", "status" => "valid" },
          { "id" => "s2", "feed_url" => "https://two.example.com/feed.xml", "title" => "Two", "website_url" => "https://two.example.com", "status" => "valid" }
        ],
        selected_ids: %w[s1 s2]
      )
      history = SourceMonitor::ImportHistory.create!(user_id: @user.id, bulk_settings: {})

      ImportOpmlJob.perform_now(session.id, history.id)

      favicon_jobs = enqueued_jobs.select { |j| j["job_class"] == "SourceMonitor::FaviconFetchJob" }
      assert_equal 2, favicon_jobs.size
    end

    test "OPML import does not enqueue FaviconFetchJob for sources without website_url" do
      session = create_import_session(
        parsed_sources: [
          { "id" => "s1", "feed_url" => "https://no-site.example.com/feed.xml", "title" => "No Site", "website_url" => nil, "status" => "valid" }
        ],
        selected_ids: %w[s1]
      )
      history = SourceMonitor::ImportHistory.create!(user_id: @user.id, bulk_settings: {})

      ImportOpmlJob.perform_now(session.id, history.id)

      favicon_jobs = enqueued_jobs.select { |j| j["job_class"] == "SourceMonitor::FaviconFetchJob" }
      assert_equal 0, favicon_jobs.size
    end

    test "OPML import does not enqueue FaviconFetchJob when favicons disabled" do
      SourceMonitor.config.favicons.enabled = false

      session = create_import_session(
        parsed_sources: [
          { "id" => "s1", "feed_url" => "https://disabled.example.com/feed.xml", "title" => "Disabled", "website_url" => "https://disabled.example.com", "status" => "valid" }
        ],
        selected_ids: %w[s1]
      )
      history = SourceMonitor::ImportHistory.create!(user_id: @user.id, bulk_settings: {})

      ImportOpmlJob.perform_now(session.id, history.id)

      favicon_jobs = enqueued_jobs.select { |j| j["job_class"] == "SourceMonitor::FaviconFetchJob" }
      assert_equal 0, favicon_jobs.size
    end

    private

    def create_import_session(parsed_sources:, selected_ids:)
      SourceMonitor::ImportSession.create!(
        user_id: @user.id,
        current_step: "confirm",
        parsed_sources: parsed_sources,
        selected_source_ids: selected_ids,
        bulk_settings: {}
      )
    end

    def configure_authentication(user)
      SourceMonitor.configure do |config|
        config.authentication.current_user_method = :current_user
        config.authentication.user_signed_in_method = :user_signed_in?

        config.authentication.authenticate_with lambda { |controller|
          controller.singleton_class.define_method(:current_user) { user }
          controller.singleton_class.define_method(:user_signed_in?) { user.present? }
        }

        config.authentication.authorize_with lambda { |_controller|
          true
        }
      end
    end
  end
end
