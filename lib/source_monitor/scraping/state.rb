# frozen_string_literal: true

module SourceMonitor
  module Scraping
    # Centralizes scrape status transitions so jobs, schedulers, and UI helpers
    # keep item states consistent and broadcast changes in one place.
    module State
      extend self

      IN_FLIGHT_STATUSES = %w[pending processing].freeze

      def mark_pending!(item, broadcast: false, lock: true)
        update_status(item, "pending", broadcast:, lock:)
      end

      def mark_processing!(item, broadcast: true, lock: true)
        update_status(item, "processing", broadcast:, lock:)
      end

      def mark_failed!(item, broadcast: true, lock: true, failed_at: Time.current)
        update_status(
          item,
          "failed",
          broadcast:,
          lock:,
          extra: { scraped_at: failed_at || Time.current }
        )
      end

      def clear_inflight!(item, broadcast: true, lock: true)
        with_item(item, lock:) do |record|
          next unless in_flight?(record.scrape_status)

          record.update_columns(scrape_status: nil)
          record.assign_attributes(scrape_status: nil)
        end

        broadcast_item(item) if broadcast
      end

      def in_flight?(status)
        IN_FLIGHT_STATUSES.include?(status.to_s)
      end

      private

      def update_status(item, status, broadcast:, lock:, extra: {})
        with_item(item, lock:) do |record|
          attributes = { scrape_status: status }.merge(extra.compact)
          record.update_columns(attributes)
          record.assign_attributes(attributes)
        end

        broadcast_item(item) if broadcast
      end

      def with_item(item, lock:)
        return unless item

        if lock
          item.with_lock do
            item.reload
            yield(item)
          end
        else
          yield(item)
        end
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def broadcast_item(item)
        SourceMonitor::Realtime.broadcast_item(item)
      rescue StandardError => e
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn("[SourceMonitor::Scraping::State] Broadcast failed: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
