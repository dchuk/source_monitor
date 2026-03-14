# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ImportHistoryDismissalsControllerTest < ActionDispatch::IntegrationTest
    include SourceMonitor::Engine.routes.url_helpers
    fixtures :users

    setup do
      @user = users(:admin)
      configure_authentication(@user)
      @import_history = ImportHistory.create!(
        user_id: @user.id,
        imported_sources: [ { "id" => 1, "feed_url" => "https://example.com/feed.xml", "name" => "Example" } ],
        failed_sources: [],
        skipped_duplicates: [],
        started_at: 1.minute.ago,
        completed_at: Time.current
      )
    end

    teardown do
      SourceMonitor.reset_configuration!
    end

    test "create sets dismissed_at via turbo stream" do
      assert_nil @import_history.dismissed_at

      post import_history_dismissal_path(@import_history), as: :turbo_stream

      assert_response :success
      @import_history.reload
      assert_not_nil @import_history.dismissed_at
      assert_includes @response.body, "source_monitor_import_history_panel"
      assert_includes @response.body, "remove"
    end

    test "create redirects for html format" do
      post import_history_dismissal_path(@import_history)

      assert_redirected_to sources_path
      @import_history.reload
      assert_not_nil @import_history.dismissed_at
    end

    test "create returns not found for nonexistent import history" do
      post import_history_dismissal_path(import_history_id: 0), as: :turbo_stream

      assert_response :not_found
    end

    test "create returns not found when dismissing another user's import history" do
      other_user = users(:viewer)
      other_import_history = ImportHistory.create!(
        user_id: other_user.id,
        imported_sources: [ { "id" => 2, "feed_url" => "https://example.com/other.xml", "name" => "Other" } ],
        failed_sources: [],
        skipped_duplicates: [],
        started_at: 1.minute.ago,
        completed_at: Time.current
      )

      post import_history_dismissal_path(other_import_history), as: :turbo_stream

      assert_response :not_found
      other_import_history.reload
      assert_nil other_import_history.dismissed_at
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
      end
    end
  end
end
