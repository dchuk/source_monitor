# frozen_string_literal: true

module SourceMonitor
  module Fetching
    class FeedFetcher
      class SourceUpdater
        attr_reader :source, :adaptive_interval

        def initialize(source:, adaptive_interval:)
          @source = source
          @adaptive_interval = adaptive_interval
        end

        def update_source_for_success(response, duration_ms, feed, feed_signature, content_changed: nil, entries_digest: nil)
          attributes = {
            last_fetched_at: Time.current,
            last_fetch_duration_ms: duration_ms,
            last_http_status: response.status,
            last_error: nil,
            last_error_at: nil,
            failure_count: 0,
            feed_format: derive_feed_format(feed)
          }

          if (etag = response.headers["etag"] || response.headers["ETag"])
            attributes[:etag] = etag
          end

          if (last_modified_header = response.headers["last-modified"] || response.headers["Last-Modified"])
            parsed_time = parse_http_time(last_modified_header)
            attributes[:last_modified] = parsed_time if parsed_time
          end

          # Use explicit content_changed if provided, otherwise fall back to feed signature comparison
          changed = content_changed.nil? ? feed_signature_changed?(feed_signature) : content_changed
          adaptive_interval.apply_adaptive_interval!(attributes, content_changed: changed)
          attributes[:metadata] = updated_metadata(feed_signature: feed_signature, entries_digest: entries_digest)
          reset_retry_state!(attributes)
          source.update!(attributes)
          enqueue_favicon_fetch_if_needed
        end

        def update_source_for_not_modified(response, duration_ms)
          attributes = {
            last_fetched_at: Time.current,
            last_fetch_duration_ms: duration_ms,
            last_http_status: response.status,
            last_error: nil,
            last_error_at: nil,
            failure_count: 0
          }

          if (etag = response.headers["etag"] || response.headers["ETag"])
            attributes[:etag] = etag
          end

          if (last_modified_header = response.headers["last-modified"] || response.headers["Last-Modified"])
            parsed_time = parse_http_time(last_modified_header)
            attributes[:last_modified] = parsed_time if parsed_time
          end

          adaptive_interval.apply_adaptive_interval!(attributes, content_changed: false)
          attributes[:metadata] = updated_metadata
          reset_retry_state!(attributes)
          source.update!(attributes)
        end

        def update_source_for_failure(error, duration_ms)
          now = Time.current
          attrs = {
            last_fetched_at: now,
            last_fetch_duration_ms: duration_ms,
            last_http_status: error.http_status,
            last_error: error.message,
            last_error_at: now,
            failure_count: source.failure_count.to_i + 1
          }

          adaptive_interval.apply_adaptive_interval!(attrs, content_changed: false, failure: true)
          attrs[:metadata] = updated_metadata
          decision = apply_retry_strategy!(attrs, error, now)
          source.update!(attrs)
          decision
        end

        def create_fetch_log(response:, duration_ms:, started_at:, success:, feed: nil, error: nil, body: nil, feed_signature: nil,
                             items_created: 0, items_updated: 0, items_failed: 0, item_errors: [])
          source.fetch_logs.create!(
            success:,
            started_at: started_at,
            completed_at: started_at + (duration_ms / 1000.0),
            duration_ms: duration_ms,
            http_status: response&.status,
            http_response_headers: normalized_headers(response&.headers),
            feed_size_bytes: body&.bytesize,
            items_in_feed: feed&.respond_to?(:entries) ? feed.entries.size : nil,
            items_created: items_created,
            items_updated: items_updated,
            items_failed: items_failed,
            error_class: error&.class&.name,
            error_message: error&.message,
            error_backtrace: error_backtrace(error),
            metadata: feed_metadata(feed, error: error, feed_signature: feed_signature, item_errors: item_errors)
          )
        end

        def elapsed_ms(started_at)
          ((Time.current - started_at) * 1000.0).round
        end

        def feed_signature_changed?(feed_signature)
          return false if feed_signature.blank?

          (source.metadata || {}).fetch("last_feed_signature", nil) != feed_signature
        end

        def updated_metadata(feed_signature: nil, entries_digest: nil)
          metadata = (source.metadata || {}).dup
          metadata.delete("dynamic_fetch_interval_seconds")
          metadata["last_feed_signature"] = feed_signature if feed_signature.present?
          metadata["last_entries_digest"] = entries_digest if entries_digest.present?
          metadata
        end

        def parse_http_time(value)
          return if value.blank?

          Time.httpdate(value)
        rescue ArgumentError
          nil
        end

        private

        def reset_retry_state!(attributes)
          attributes[:fetch_retry_attempt] = 0
          attributes[:fetch_circuit_opened_at] = nil
          attributes[:fetch_circuit_until] = nil
        end

        def enqueue_favicon_fetch_if_needed
          return unless defined?(ActiveStorage)
          return unless SourceMonitor.config.favicons.enabled?
          return if source.website_url.blank?
          return if source.respond_to?(:favicon) && source.favicon.attached?

          last_attempt = source.metadata&.dig("favicon_last_attempted_at")
          if last_attempt.present?
            cooldown_days = SourceMonitor.config.favicons.retry_cooldown_days
            return if Time.parse(last_attempt) > cooldown_days.days.ago
          end

          SourceMonitor::FaviconFetchJob.perform_later(source.id)
        rescue StandardError => error
          Rails.logger.warn(
            "[SourceMonitor::SourceUpdater] Failed to enqueue favicon fetch for source #{source.id}: #{error.message}"
          ) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        end

        def apply_retry_strategy!(attributes, error, now)
          decision = SourceMonitor::Fetching::RetryPolicy.new(source:, error:, now:).decision

          if decision.open_circuit?
            attributes[:fetch_retry_attempt] = 0
            attributes[:fetch_circuit_opened_at] = now
            attributes[:fetch_circuit_until] = decision.circuit_until
            attributes[:next_fetch_at] = decision.circuit_until
            attributes[:backoff_until] = decision.circuit_until
          elsif decision.retry?
            attributes[:fetch_retry_attempt] = decision.next_attempt
            attributes[:fetch_circuit_opened_at] = nil
            attributes[:fetch_circuit_until] = nil
            unless source.adaptive_fetching_enabled? == false
              retry_at = now + decision.wait
              current_next = attributes[:next_fetch_at]
              attributes[:next_fetch_at] = [ current_next, retry_at ].compact.min
              attributes[:backoff_until] = retry_at
            end
          else
            attributes[:fetch_retry_attempt] = 0
          end

          decision
        rescue StandardError => policy_error
          Rails.logger.error(
            "[SourceMonitor] Failed to apply retry strategy for source #{source.id}: #{policy_error.class} - #{policy_error.message}"
          ) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          attributes[:fetch_retry_attempt] ||= 0
          attributes[:fetch_circuit_opened_at] ||= nil
          attributes[:fetch_circuit_until] ||= nil
          nil
        end

        def derive_feed_format(feed)
          return unless feed

          feed.class.name.split("::").last.underscore
        end

        def feed_metadata(feed, error: nil, feed_signature: nil, item_errors: [])
          metadata = {}
          metadata[:parser] = feed.class.name if feed
          metadata[:error_code] = error.code if error&.respond_to?(:code)
          metadata[:feed_signature] = feed_signature if feed_signature
          metadata[:item_errors] = item_errors if item_errors.present?
          metadata
        end

        def normalized_headers(headers)
          return {} unless headers

          headers.to_h.transform_keys { |key| key.to_s.downcase }
        end

        def error_backtrace(error)
          return if error.nil? || error.original_error.nil?

          Array(error.original_error.backtrace).first(20).join("\n")
        end
      end
    end
  end
end
