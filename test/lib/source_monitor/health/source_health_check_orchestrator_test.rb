# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Health
    class SourceHealthCheckOrchestratorTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        @source = create_source!(name: "Orchestrator Test Source", health_status: "working")
      end

      test "calls health check and broadcasts on success" do
        result = SourceHealthCheck::Result.new(log: nil, success?: true, error: nil)

        checker = Minitest::Mock.new
        checker.expect :call, result

        broadcast_source_called = false
        broadcast_toast_called = false
        toast_args = nil

        SourceMonitor::Realtime.stub(:broadcast_source, ->(_source) { broadcast_source_called = true }) do
          SourceMonitor::Realtime.stub(:broadcast_toast, ->(**kwargs) { broadcast_toast_called = true; toast_args = kwargs }) do
            SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**_args) { checker }) do
              SourceHealthCheckOrchestrator.new(@source).call
            end
          end
        end

        checker.verify
        assert broadcast_source_called
        assert broadcast_toast_called
        assert_equal :success, toast_args[:level]
        assert_includes toast_args[:message], "succeeded"
      end

      test "broadcasts failure toast when result is not successful" do
        log = Struct.new(:http_status).new(502)
        error = StandardError.new("bad gateway")
        result = SourceHealthCheck::Result.new(log: log, success?: false, error: error)

        checker = Minitest::Mock.new
        checker.expect :call, result

        toast_args = nil

        SourceMonitor::Realtime.stub(:broadcast_source, ->(_source) { }) do
          SourceMonitor::Realtime.stub(:broadcast_toast, ->(**kwargs) { toast_args = kwargs }) do
            SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**_args) { checker }) do
              SourceHealthCheckOrchestrator.new(@source).call
            end
          end
        end

        checker.verify
        assert_equal :error, toast_args[:level]
        assert_includes toast_args[:message], "HTTP 502"
        assert_includes toast_args[:message], "bad gateway"
      end

      test "broadcasts failure toast with no http_status or error message" do
        result = SourceHealthCheck::Result.new(log: nil, success?: false, error: nil)

        checker = Minitest::Mock.new
        checker.expect :call, result

        toast_args = nil

        SourceMonitor::Realtime.stub(:broadcast_source, ->(_source) { }) do
          SourceMonitor::Realtime.stub(:broadcast_toast, ->(**kwargs) { toast_args = kwargs }) do
            SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**_args) { checker }) do
              SourceHealthCheckOrchestrator.new(@source).call
            end
          end
        end

        checker.verify
        assert_equal :error, toast_args[:level]
        assert_includes toast_args[:message], "Health check failed"
      end

      test "triggers fetch when source is in degraded status" do
        @source.update_columns(health_status: "declining")
        result = SourceHealthCheck::Result.new(log: nil, success?: true, error: nil)

        checker = Minitest::Mock.new
        checker.expect :call, result

        SourceMonitor::Realtime.stub(:broadcast_source, ->(_source) { }) do
          SourceMonitor::Realtime.stub(:broadcast_toast, ->(**kwargs) { }) do
            SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**_args) { checker }) do
              assert_enqueued_with(job: SourceMonitor::FetchFeedJob) do
                SourceHealthCheckOrchestrator.new(@source).call
              end
            end
          end
        end

        checker.verify
      end

      test "triggers fetch when source is in failing status" do
        @source.update_columns(health_status: "failing")
        result = SourceHealthCheck::Result.new(log: nil, success?: true, error: nil)

        checker = Minitest::Mock.new
        checker.expect :call, result

        SourceMonitor::Realtime.stub(:broadcast_source, ->(_source) { }) do
          SourceMonitor::Realtime.stub(:broadcast_toast, ->(**kwargs) { }) do
            SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**_args) { checker }) do
              assert_enqueued_with(job: SourceMonitor::FetchFeedJob) do
                SourceHealthCheckOrchestrator.new(@source).call
              end
            end
          end
        end

        checker.verify
      end

      test "does not trigger fetch when source is working" do
        @source.update_columns(health_status: "working")
        result = SourceHealthCheck::Result.new(log: nil, success?: true, error: nil)

        checker = Minitest::Mock.new
        checker.expect :call, result

        SourceMonitor::Realtime.stub(:broadcast_source, ->(_source) { }) do
          SourceMonitor::Realtime.stub(:broadcast_toast, ->(**kwargs) { }) do
            SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**_args) { checker }) do
              assert_no_enqueued_jobs(only: SourceMonitor::FetchFeedJob) do
                SourceHealthCheckOrchestrator.new(@source).call
              end
            end
          end
        end

        checker.verify
      end

      test "does not trigger fetch when result is not successful" do
        @source.update_columns(health_status: "declining")
        result = SourceHealthCheck::Result.new(log: nil, success?: false, error: nil)

        checker = Minitest::Mock.new
        checker.expect :call, result

        SourceMonitor::Realtime.stub(:broadcast_source, ->(_source) { }) do
          SourceMonitor::Realtime.stub(:broadcast_toast, ->(**kwargs) { }) do
            SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**_args) { checker }) do
              assert_no_enqueued_jobs(only: SourceMonitor::FetchFeedJob) do
                SourceHealthCheckOrchestrator.new(@source).call
              end
            end
          end
        end

        checker.verify
      end

      test "handles unexpected error by logging, recording failure, and broadcasting" do
        error = RuntimeError.new("unexpected boom")

        failing_checker = Object.new
        failing_checker.define_singleton_method(:call) { raise error }

        broadcast_source_called = false
        toast_args = nil

        SourceMonitor::Realtime.stub(:broadcast_source, ->(_source) { broadcast_source_called = true }) do
          SourceMonitor::Realtime.stub(:broadcast_toast, ->(**kwargs) { toast_args = kwargs }) do
            SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**_args) { failing_checker }) do
              assert_difference("SourceMonitor::HealthCheckLog.count", 1) do
                SourceHealthCheckOrchestrator.new(@source).call
              end
            end
          end
        end

        assert broadcast_source_called
        assert_equal :error, toast_args[:level]
        assert_includes toast_args[:message], "unexpected boom"

        log = SourceMonitor::HealthCheckLog.where(source: @source).last
        assert_equal false, log.success
        assert_equal "RuntimeError", log.error_class
        assert_equal "unexpected boom", log.error_message
      end

      test "record_unexpected_failure swallows secondary errors" do
        error = RuntimeError.new("primary error")

        failing_checker = Object.new
        failing_checker.define_singleton_method(:call) { raise error }

        # Stub HealthCheckLog.create! to raise (simulating DB failure during error recording)
        SourceMonitor::HealthCheckLog.stub(:create!, ->(**_args) { raise StandardError, "DB down" }) do
          SourceMonitor::Realtime.stub(:broadcast_source, ->(_source) { }) do
            SourceMonitor::Realtime.stub(:broadcast_toast, ->(**kwargs) { }) do
              SourceMonitor::Health::SourceHealthCheck.stub(:new, ->(**_args) { failing_checker }) do
                assert_nothing_raised do
                  SourceHealthCheckOrchestrator.new(@source).call
                end
              end
            end
          end
        end
      end

      test "log_error writes to Rails logger" do
        error = RuntimeError.new("test error")
        orchestrator = SourceHealthCheckOrchestrator.new(@source)

        logged_messages = []
        mock_logger = Object.new
        mock_logger.define_singleton_method(:error) { |msg| logged_messages << msg }

        Rails.stub(:logger, mock_logger) do
          orchestrator.send(:log_error, error)
        end

        assert_equal 1, logged_messages.size
        assert_includes logged_messages.first, "RuntimeError"
        assert_includes logged_messages.first, "test error"
      end
    end
  end
end
