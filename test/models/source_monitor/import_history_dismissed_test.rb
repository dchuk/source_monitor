# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ImportHistoryDismissedTest < ActiveSupport::TestCase
    fixtures :users

    setup do
      SourceMonitor.reset_configuration!
      @user_id = users(:admin).id
    end

    test "not_dismissed scope excludes dismissed records" do
      active = ImportHistory.create!(user_id: @user_id, imported_sources: [], failed_sources: [], skipped_duplicates: [])
      dismissed = ImportHistory.create!(user_id: @user_id, imported_sources: [], failed_sources: [], skipped_duplicates: [], dismissed_at: Time.current)

      results = ImportHistory.not_dismissed
      assert_includes results, active
      assert_not_includes results, dismissed
    end

    test "not_dismissed scope includes records with nil dismissed_at" do
      record = ImportHistory.create!(user_id: @user_id, imported_sources: [], failed_sources: [], skipped_duplicates: [])

      assert_nil record.dismissed_at
      assert_includes ImportHistory.not_dismissed, record
    end

    test "dismissed imports are filtered from sources index query" do
      ImportHistory.create!(user_id: @user_id, imported_sources: [ { "id" => 1 } ], failed_sources: [], skipped_duplicates: [], dismissed_at: Time.current)
      visible = ImportHistory.create!(user_id: @user_id, imported_sources: [ { "id" => 2 } ], failed_sources: [], skipped_duplicates: [])

      results = ImportHistory.not_dismissed.recent_for(@user_id).limit(5)
      assert_equal [ visible ], results.to_a
    end
  end
end
