# frozen_string_literal: true

module SourceMonitor
  class FetchFeedJob < ApplicationJob
    FETCH_CONCURRENCY_BASE_WAIT = 30.seconds
    FETCH_CONCURRENCY_MAX_WAIT = 5.minutes
    EARLY_EXECUTION_LEEWAY = 30.seconds

    source_monitor_queue :fetch

    SCHEDULED_CONCURRENCY_MAX_ATTEMPTS = 5

    discard_on ActiveJob::DeserializationError

    rescue_from SourceMonitor::Fetching::FetchRunner::ConcurrencyError do |error|
      handle_concurrency_error(error)
    end

    def perform(source_id, force: false)
      @source_id = source_id
      @force = force

      source = SourceMonitor::Source.find_by(id: source_id)
      return unless source

      @source = source
      return unless should_run?(source, force: force)

      SourceMonitor::Fetching::FetchRunner.new(source: source, force: force).run
    rescue SourceMonitor::Fetching::FetchError => error
      handle_transient_error(source, error)
    end

    private

    def handle_concurrency_error(error)
      if @force
        log_force_fetch_skipped
        @source&.update_columns(fetch_status: "idle") if @source&.fetch_status == "queued"
      else
        attempt = executions
        if attempt < SCHEDULED_CONCURRENCY_MAX_ATTEMPTS
          retry_job wait: concurrency_backoff_wait(attempt)
        else
          log_concurrency_exhausted
          @source&.update_columns(fetch_status: "idle") if @source&.fetch_status == "queued"
        end
      end
    end

    def concurrency_backoff_wait(attempt)
      base = FETCH_CONCURRENCY_BASE_WAIT.to_i
      exponential = base * (2**attempt)
      capped = [ exponential, FETCH_CONCURRENCY_MAX_WAIT.to_i ].min
      jitter = rand(0..(capped * 0.25).to_i)
      (capped + jitter).seconds
    end

    def log_concurrency_exhausted
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.info(
        "[SourceMonitor::FetchFeedJob] Concurrency retries exhausted for source #{@source_id}, " \
        "discarding (another worker is fetching this source)"
      )
    rescue StandardError
      nil
    end

    def log_force_fetch_skipped
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.info("[SourceMonitor::FetchFeedJob] Fetch already in progress for source #{@source_id}, skipping force-fetch")
    rescue StandardError
      nil
    end

    def should_run?(source, force:)
      return true if force

      status = source.fetch_status.to_s
      return true if %w[queued fetching].include?(status)

      next_fetch_at = source.next_fetch_at
      return true if next_fetch_at.blank?

      next_fetch_at <= Time.current + EARLY_EXECUTION_LEEWAY
    end

    def handle_transient_error(source, error)
      raise error unless transient_error?(error) && source

      decision = SourceMonitor::Fetching::RetryPolicy.new(source:, error:, now: Time.current).decision
      return raise error unless decision

      result = SourceMonitor::Fetching::RetryOrchestrator.call(source:, error:, decision:)
      raise error unless result.retry_enqueued?
    rescue StandardError => policy_error
      log_retry_failure(source, error, policy_error)
      raise error
    end

    def transient_error?(error)
      error.is_a?(SourceMonitor::Fetching::FetchError)
    end

    def log_retry_failure(source, original_error, policy_error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      message = "[SourceMonitor::FetchFeedJob] Failed to schedule retry for source #{source&.id}: " \
                "#{original_error.class}: #{original_error.message} (policy error: #{policy_error.class})"
      Rails.logger.error(message)
    rescue StandardError
      nil
    end
  end
end
