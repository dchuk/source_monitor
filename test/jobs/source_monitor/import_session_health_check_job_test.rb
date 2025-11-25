# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ImportSessionHealthCheckJobTest < ActiveJob::TestCase
    fixtures :users

    setup do
      @admin = users(:admin)
    end

    test "stores result, deselects unhealthy sources, and marks completion" do
      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "health_check",
        parsed_sources: [
          { "id" => "one", "feed_url" => "https://example.com/feed.xml", "status" => "valid" }
        ],
        selected_source_ids: [ "one" ],
        health_checks_active: true,
        health_check_target_ids: [ "one" ]
      )

      result = SourceMonitor::Health::ImportSourceHealthCheck::Result.new(
        status: "unhealthy",
        error_message: "timeout",
        http_status: 500
      )

      checker = Minitest::Mock.new
      checker.expect :call, result

      SourceMonitor::Health::ImportSourceHealthCheck.stub(:new, ->(**_args) { checker }) do
        perform_enqueued_jobs do
          SourceMonitor::ImportSessionHealthCheckJob.perform_later(session.id, "one")
        end
      end

      checker.verify
      session.reload
      assert_equal "unhealthy", session.parsed_sources.first["health_status"]
      assert_equal "timeout", session.parsed_sources.first["health_error"]
      assert_empty session.selected_source_ids
      assert session.health_check_completed_at.present?
    end

    test "skips updates when session is inactive" do
      session = SourceMonitor::ImportSession.create!(
        user_id: @admin.id,
        current_step: "configure",
        parsed_sources: [ { "id" => "one", "feed_url" => "https://example.com/feed.xml" } ],
        selected_source_ids: [],
        health_checks_active: false,
        health_check_target_ids: []
      )

      perform_enqueued_jobs do
        SourceMonitor::ImportSessionHealthCheckJob.perform_later(session.id, "one")
      end

      session.reload
      assert_nil session.parsed_sources.first["health_status"]
    end
  end
end
