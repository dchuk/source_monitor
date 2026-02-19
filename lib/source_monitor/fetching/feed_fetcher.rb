# frozen_string_literal: true

require "time"
require "digest"
require "source_monitor/http"
require "source_monitor/fetching/fetch_error"
require "source_monitor/fetching/retry_policy"
require "source_monitor/items/item_creator"
require "source_monitor/fetching/feed_fetcher/adaptive_interval"
require "source_monitor/fetching/feed_fetcher/source_updater"
require "source_monitor/fetching/feed_fetcher/entry_processor"

module SourceMonitor
  module Fetching
    class FeedFetcher
      Result = Struct.new(:status, :feed, :response, :body, :error, :item_processing, :retry_decision, keyword_init: true)
      EntryProcessingResult = Struct.new(
        :created,
        :updated,
        :unchanged,
        :failed,
        :items,
        :errors,
        :created_items,
        :updated_items,
        keyword_init: true
      )
      ResponseWrapper = Struct.new(:status, :headers, :body, keyword_init: true)

      MIN_FETCH_INTERVAL = AdaptiveInterval::MIN_FETCH_INTERVAL
      MAX_FETCH_INTERVAL = AdaptiveInterval::MAX_FETCH_INTERVAL
      INCREASE_FACTOR = AdaptiveInterval::INCREASE_FACTOR
      DECREASE_FACTOR = AdaptiveInterval::DECREASE_FACTOR
      FAILURE_INCREASE_FACTOR = AdaptiveInterval::FAILURE_INCREASE_FACTOR
      JITTER_PERCENT = AdaptiveInterval::JITTER_PERCENT

      attr_reader :source, :client, :jitter_proc

      def initialize(source:, client: nil, jitter: nil)
        @source = source
        @client = client
        @jitter_proc = jitter
      end

      def call
        attempt_started_at = Time.current
        instrumentation_payload = base_instrumentation_payload
        started_monotonic = SourceMonitor::Instrumentation.monotonic_time
        result = nil

        SourceMonitor::Instrumentation.fetch_start(instrumentation_payload)

        result = perform_fetch(attempt_started_at, instrumentation_payload)
      rescue FetchError => error
        result = handle_failure(error, started_at: attempt_started_at, instrumentation_payload:)
      rescue StandardError => error
        fetch_error = UnexpectedResponseError.new(error.message, original_error: error)
        result = handle_failure(fetch_error, started_at: attempt_started_at, instrumentation_payload:)
      ensure
        instrumentation_payload[:duration_ms] ||= duration_since(started_monotonic)
        SourceMonitor::Instrumentation.fetch_finish(instrumentation_payload)
        return result
      end

      private

      def base_instrumentation_payload
        {
          source_id: source.id,
          feed_url: source.feed_url
        }
      end

      def duration_since(started_monotonic)
        ((SourceMonitor::Instrumentation.monotonic_time - started_monotonic) * 1000.0).round(2)
      end

      def perform_fetch(started_at, instrumentation_payload)
        response = perform_request
        handle_response(response, started_at, instrumentation_payload)
      rescue TimeoutError, ConnectionError, HTTPError, ParsingError => error
        raise error
      rescue Faraday::TimeoutError => error
        raise TimeoutError.new(error.message, original_error: error)
      rescue Faraday::ConnectionFailed => error
        raise ConnectionError.new(error.message, original_error: error)
      rescue Faraday::SSLError => error
        attempt_aia_recovery(error, started_at, instrumentation_payload) ||
          raise(ConnectionError.new(error.message, original_error: error))
      rescue Faraday::ClientError => error
        raise build_http_error_from_faraday(error)
      rescue Faraday::Error => error
        raise FetchError.new(error.message, original_error: error)
      end

      def perform_request
        connection.get(source.feed_url)
      end

      def connection
        @connection ||= (client || SourceMonitor::HTTP.client(headers: request_headers))
      end

      def request_headers
        headers = (source.custom_headers || {}).transform_keys { |key| key.to_s }
        headers["If-None-Match"] = source.etag if source.etag.present?
        if source.last_modified.present?
          headers["If-Modified-Since"] = source.last_modified.httpdate
        end
        headers
      end

      def handle_response(response, started_at, instrumentation_payload)
        case response.status
        when 200
          handle_success(response, started_at, instrumentation_payload)
        when 304
          handle_not_modified(response, started_at, instrumentation_payload)
        else
          raise HTTPError.new(status: response.status, response: response)
        end
      end

      def handle_success(response, started_at, instrumentation_payload)
        duration_ms = source_updater.elapsed_ms(started_at)
        body = response.body
        feed_body_signature = body_digest(body)
        feed = parse_feed(body, response)

        if source_updater.feed_signature_changed?(feed_body_signature)
          processing = entry_processor.process_feed_entries(feed)
          content_changed = entries_digest_changed?(feed)
        else
          processing = EntryProcessingResult.new(
            created: 0,
            updated: 0,
            unchanged: 0,
            failed: 0,
            items: [],
            errors: [],
            created_items: [],
            updated_items: []
          )
          content_changed = false
        end

        feed_entries_digest = entries_digest(feed)
        source_updater.update_source_for_success(response, duration_ms, feed, feed_body_signature, content_changed: content_changed, entries_digest: feed_entries_digest)
        source_updater.create_fetch_log(
          response: response,
          duration_ms: duration_ms,
          started_at: started_at,
          feed: feed,
          success: true,
          body: body,
          feed_signature: feed_body_signature,
          items_created: processing.created,
          items_updated: processing.updated,
          items_failed: processing.failed,
          item_errors: processing.errors
        )

        instrumentation_payload[:success] = true
        instrumentation_payload[:status] = :fetched
        instrumentation_payload[:http_status] = response.status
        instrumentation_payload[:parser] = feed.class.name if feed
        instrumentation_payload[:items_created] = processing.created
        instrumentation_payload[:items_updated] = processing.updated
        instrumentation_payload[:items_failed] = processing.failed
        instrumentation_payload[:retry_attempt] = 0

        Result.new(status: :fetched, feed:, response:, body:, item_processing: processing)
      end

      def handle_not_modified(response, started_at, instrumentation_payload)
        duration_ms = source_updater.elapsed_ms(started_at)

        source_updater.update_source_for_not_modified(response, duration_ms)
        source_updater.create_fetch_log(
          response: response,
          duration_ms: duration_ms,
          started_at: started_at,
          success: true
        )

        instrumentation_payload[:success] = true
        instrumentation_payload[:status] = :not_modified
        instrumentation_payload[:http_status] = response.status
        instrumentation_payload[:items_created] = 0
        instrumentation_payload[:items_updated] = 0
        instrumentation_payload[:items_failed] = 0
        instrumentation_payload[:retry_attempt] = 0

        Result.new(
          status: :not_modified,
          response: response,
          body: nil,
          item_processing: EntryProcessingResult.new(
            created: 0,
            updated: 0,
            unchanged: 0,
            failed: 0,
            items: [],
            errors: [],
            created_items: [],
            updated_items: []
          )
        )
      end

      def parse_feed(body, response)
        Feedjira.parse(body)
      rescue StandardError => error
        raise ParsingError.new(error.message, response: response, original_error: error)
      end

      def handle_failure(error, started_at:, instrumentation_payload:)
        response = error.response
        body = response&.body
        duration_ms = source_updater.elapsed_ms(started_at)

        retry_decision = source_updater.update_source_for_failure(error, duration_ms)
        source_updater.create_fetch_log(
          response: response,
          duration_ms: duration_ms,
          started_at: started_at,
          success: false,
          error: error,
          body: body
        )

        instrumentation_payload[:success] = false
        instrumentation_payload[:status] = :failed
        instrumentation_payload[:error_class] = error.class.name
        instrumentation_payload[:error_message] = error.message
        instrumentation_payload[:http_status] = error.http_status if error.http_status
        instrumentation_payload[:error_code] = error.code if error.respond_to?(:code)
        instrumentation_payload[:items_created] = 0
        instrumentation_payload[:items_updated] = 0
        instrumentation_payload[:items_failed] = 0
        instrumentation_payload[:retry_attempt] = retry_decision&.next_attempt ? retry_decision.next_attempt : 0

        Result.new(
          status: :failed,
          response: response,
          body: body,
          error: error,
          retry_decision: retry_decision,
          item_processing: EntryProcessingResult.new(
            created: 0,
            updated: 0,
            unchanged: 0,
            failed: 0,
            items: [],
            errors: [],
            created_items: [],
            updated_items: []
          )
        )
      end

      def attempt_aia_recovery(_error, started_at, instrumentation_payload)
        return if @aia_attempted

        @aia_attempted = true
        hostname = URI.parse(source.feed_url).host
        intermediate = SourceMonitor::HTTP::AIAResolver.resolve(hostname)
        return unless intermediate

        store = SourceMonitor::HTTP::AIAResolver.enhanced_cert_store([ intermediate ])
        @connection = SourceMonitor::HTTP.client(cert_store: store, headers: request_headers)
        instrumentation_payload[:aia_resolved] = true

        response = perform_request
        handle_response(response, started_at, instrumentation_payload)
      rescue StandardError
        nil
      end

      def build_http_error_from_faraday(error)
        response_hash = error.response || {}
        headers = response_hash[:headers] || response_hash[:response_headers] || {}
        ResponseWrapper.new(
          status: response_hash[:status],
          headers: headers,
          body: response_hash[:body]
        ).then do |response|
          status = response.status || 0
          message = error.message
          HTTPError.new(status: status, message: message, response: response, original_error: error)
        end
      end

      def body_digest(body)
        return if body.blank?

        Digest::SHA256.hexdigest(body)
      end

      def entries_digest(feed)
        return if feed.nil? || !feed.respond_to?(:entries)

        ids = Array(feed.entries).map do |entry|
          if entry.respond_to?(:entry_id) && entry.entry_id.present?
            entry.entry_id
          elsif entry.respond_to?(:url) && entry.url.present?
            entry.url
          elsif entry.respond_to?(:title) && entry.title.present?
            entry.title
          end
        end.compact.sort

        return if ids.empty?

        Digest::SHA256.hexdigest(ids.join("\0"))
      end

      def entries_digest_changed?(feed)
        digest = entries_digest(feed)
        return false if digest.nil?

        stored = (source.metadata || {}).fetch("last_entries_digest", nil)
        stored != digest
      end

      def adaptive_interval
        @adaptive_interval ||= AdaptiveInterval.new(source: source, jitter_proc: jitter_proc)
      end

      def source_updater
        @source_updater ||= SourceUpdater.new(source: source, adaptive_interval: adaptive_interval)
      end

      def entry_processor
        @entry_processor ||= EntryProcessor.new(source: source)
      end

      # Forwarding methods for backward compatibility with tests
      def process_feed_entries(feed) = entry_processor.process_feed_entries(feed)
      def jitter_offset(interval_seconds) = adaptive_interval.jitter_offset(interval_seconds)
      def adjusted_interval_with_jitter(interval_seconds) = adaptive_interval.adjusted_interval_with_jitter(interval_seconds)
      def updated_metadata(feed_signature: nil) = source_updater.updated_metadata(feed_signature: feed_signature)
      def feed_signature_changed?(feed_signature) = source_updater.feed_signature_changed?(feed_signature)
      def configured_seconds(minutes_value, default) = adaptive_interval.configured_seconds(minutes_value, default)
      def configured_positive(value, default) = adaptive_interval.configured_positive(value, default)
      def configured_non_negative(value, default) = adaptive_interval.configured_non_negative(value, default)
      def interval_minutes_for(interval_seconds) = adaptive_interval.interval_minutes_for(interval_seconds)
      def parse_http_time(value) = source_updater.parse_http_time(value)
      def extract_numeric(value) = adaptive_interval.extract_numeric(value)
    end
  end
end
