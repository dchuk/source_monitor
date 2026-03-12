# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Health
    class SourceHealthMonitorTest < ActiveSupport::TestCase
      include ActiveSupport::Testing::TimeHelpers

      setup do
        @source = SourceMonitor::Source.create!(
          name: "Health Source",
          feed_url: "https://example.com/healthy.xml",
          fetch_interval_minutes: 60,
          next_fetch_at: Time.current
        )

        configure_health(
          window_size: 5,
          healthy_threshold: 0.6,
          auto_pause_threshold: 0.2,
          auto_resume_threshold: 0.5,
          cooldown_minutes: 30
        )
      end

      teardown do
        restore_health_configuration
      end

      test "updates rolling success rate and health status" do
        travel_to(Time.current) do
          3.times { |index| create_fetch_log(success: true, minutes_ago: index + 1) }
          2.times { |index| create_fetch_log(success: false, minutes_ago: index + 4) }

          SourceMonitor::Health::SourceHealthMonitor.new(source: @source).call

          @source.reload
          assert_in_delta 0.6, @source.rolling_success_rate, 0.001
          assert_equal "working", @source.health_status
        end
      end

      test "auto pauses when rolling success rate falls below threshold" do
        travel_to(Time.current) do
          5.times { |index| create_fetch_log(success: false, minutes_ago: index + 1) }

          SourceMonitor::Health::SourceHealthMonitor.new(source: @source).call

          @source.reload
          assert_equal "failing", @source.health_status
          assert_not_nil @source.auto_paused_at
          assert_not_nil @source.auto_paused_until
          assert_operator @source.auto_paused_until, :>, Time.current
          assert_in_delta @source.auto_paused_until, @source.next_fetch_at, 1
        end
      end

      test "resumes automatically when success rate recovers" do
        travel_to(Time.current) do
          5.times { |index| create_fetch_log(success: false, minutes_ago: index + 1) }
          SourceMonitor::Health::SourceHealthMonitor.new(source: @source).call

          travel 31.minutes

          5.times { |index| create_fetch_log(success: true, minutes_ago: index) }

          SourceMonitor::Health::SourceHealthMonitor.new(source: @source).call

          @source.reload
          assert_equal "working", @source.health_status
          assert_nil @source.auto_paused_at
          assert_nil @source.auto_paused_until
        end
      end

      test "uses per source auto pause threshold when provided" do
        @source.update!(health_auto_pause_threshold: 0.6)

        travel_to(Time.current) do
          2.times { create_fetch_log(success: true) }
          3.times { create_fetch_log(success: false) }

          SourceMonitor::Health::SourceHealthMonitor.new(source: @source).call

          @source.reload
          assert_not_nil @source.auto_paused_until
        end
      end

      test "marks source as declining after three consecutive failures" do
        travel_to(Time.current) do
          3.times { |index| create_fetch_log(success: false, minutes_ago: index) }

          SourceMonitor::Health::SourceHealthMonitor.new(source: @source).call

          @source.reload
          assert_equal "declining", @source.health_status
        end
      end

      test "marks source as improving after consecutive recoveries" do
        travel_to(Time.current) do
          create_fetch_log(success: false, minutes_ago: 2)
          create_fetch_log(success: true, minutes_ago: 1)
          create_fetch_log(success: true, minutes_ago: 0)

          SourceMonitor::Health::SourceHealthMonitor.new(source: @source).call

          @source.reload
          assert_equal "improving", @source.health_status
        end
      end

      test "resume clears consecutive_fetch_failures" do
        travel_to(Time.current) do
          @source.update_columns(
            consecutive_fetch_failures: 5,
            auto_paused_until: 30.minutes.from_now,
            auto_paused_at: Time.current,
            health_status: "failing"
          )

          5.times { |index| create_fetch_log(success: false, minutes_ago: index + 1) }
          SourceMonitor::Health::SourceHealthMonitor.new(source: @source).call

          travel 31.minutes

          5.times { |index| create_fetch_log(success: true, minutes_ago: index) }

          SourceMonitor::Health::SourceHealthMonitor.new(source: @source).call

          @source.reload
          assert_equal 0, @source.consecutive_fetch_failures
          assert_nil @source.auto_paused_until
          assert_nil @source.auto_paused_at
        end
      end

      test "private helpers compute failure and success streaks" do
        monitor = SourceMonitor::Health::SourceHealthMonitor.new(source: @source)

        simple_log = Class.new do
          attr_reader :value

          def initialize(value)
            @value = value
          end

          def success?
            value
          end

          def success
            value
          end
        end

        logs = [
          simple_log.new(false),
          simple_log.new(false),
          simple_log.new(true)
        ]

        assert_equal 2, monitor.send(:consecutive_failures, logs)

        improving_logs = [
          simple_log.new(true),
          simple_log.new(true),
          simple_log.new(false)
        ]

        assert monitor.send(:improving_streak?, improving_logs)
        refute monitor.send(:improving_streak?, logs)
      end

      private

      def create_fetch_log(success:, minutes_ago: 0)
        started_at = Time.current - minutes_ago.minutes

        SourceMonitor::FetchLog.create!(
          source: @source,
          success: success,
          started_at: started_at,
          completed_at: started_at + 30.seconds,
          duration_ms: 30_000,
          http_status: success ? 200 : 500
        )
      end

      def configure_health(window_size:, healthy_threshold:, auto_pause_threshold:, auto_resume_threshold:, cooldown_minutes:)
        @previous_health_config = capture_health_configuration

        SourceMonitor.configure do |config|
          config.health.window_size = window_size
          config.health.healthy_threshold = healthy_threshold
          config.health.auto_pause_threshold = auto_pause_threshold
          config.health.auto_resume_threshold = auto_resume_threshold
          config.health.auto_pause_cooldown_minutes = cooldown_minutes
        end
      end

      def restore_health_configuration
        return unless @previous_health_config

        SourceMonitor.configure do |config|
          config.health.window_size = @previous_health_config[:window_size]
          config.health.healthy_threshold = @previous_health_config[:healthy_threshold]
          config.health.auto_pause_threshold = @previous_health_config[:auto_pause_threshold]
          config.health.auto_resume_threshold = @previous_health_config[:auto_resume_threshold]
          config.health.auto_pause_cooldown_minutes = @previous_health_config[:auto_pause_cooldown_minutes]
        end
      end

      def capture_health_configuration
        health = SourceMonitor.config.health
        {
          window_size: health.window_size,
          healthy_threshold: health.healthy_threshold,
          auto_pause_threshold: health.auto_pause_threshold,
          auto_resume_threshold: health.auto_resume_threshold,
          auto_pause_cooldown_minutes: health.auto_pause_cooldown_minutes
        }
      end
    end
  end
end
