# frozen_string_literal: true

require "test_helper"
require_relative "../../support/shared_loggable_tests"

module SourceMonitor
  class HealthCheckLogTest < ActiveSupport::TestCase
    include SharedLoggableTests

    setup do
      @source = create_source!(name: "Health Check Test")
    end

    def build_loggable(overrides = {})
      HealthCheckLog.new({ source: @source, started_at: Time.current }.merge(overrides))
    end

    test "belongs to source" do
      log = HealthCheckLog.create!(source: @source, started_at: Time.current, success: true)

      assert_equal @source, log.source
    end

    test "validates source presence" do
      log = HealthCheckLog.new(started_at: Time.current)

      assert_not log.valid?
      assert_includes log.errors[:source], "must exist"
    end

    test "http_response_headers defaults to empty hash" do
      log = HealthCheckLog.new(source: @source, started_at: Time.current)

      assert_equal({}, log.http_response_headers)
    end

    test "creates log entry via after_save sync" do
      log = HealthCheckLog.create!(source: @source, started_at: Time.current, success: true)

      assert log.log_entry.present?, "expected a LogEntry to be synced after save"
      assert_equal @source, log.log_entry.source
    end
  end
end
