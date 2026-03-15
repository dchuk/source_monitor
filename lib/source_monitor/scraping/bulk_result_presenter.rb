# frozen_string_literal: true

module SourceMonitor
  module Scraping
    # Presenter for building flash messages from BulkSourceScraper results
    # Extracts complex message formatting logic from the controller
    class BulkResultPresenter
      attr_reader :result

      def initialize(result:)
        @result = result
      end

      def to_flash_payload
        case result.status
        when :success
          build_success_payload
        when :partial
          build_partial_payload
        else
          build_error_payload
        end
      end

      private

      def pluralize(count, word)
        "#{count} #{count == 1 ? word : word.pluralize}"
      end

      def build_success_payload
        label = BulkSourceScraper.selection_label(result.selection)
        pluralized_enqueued = pluralize(result.enqueued_count, "item")

        message = "Queued scraping for #{pluralized_enqueued} from the #{label}."

        if result.already_enqueued_count.positive?
          pluralized_already = pluralize(result.already_enqueued_count, "item")
          message = "#{message} #{pluralized_already.capitalize} already in progress."
        end

        { flash_key: :notice, message:, level: :success }
      end

      def build_partial_payload
        label = BulkSourceScraper.selection_label(result.selection)
        parts = []

        if result.enqueued_count.positive?
          pluralized_enqueued = pluralize(result.enqueued_count, "item")
          parts << "Queued #{pluralized_enqueued} from the #{label}"
        end

        if result.already_enqueued_count.positive?
          pluralized_already = pluralize(result.already_enqueued_count, "item")
          parts << "#{pluralized_already.capitalize} already in progress"
        end

        if result.rate_limited?
          limit = SourceMonitor.config.scraping.max_in_flight_per_source
          parts << "Stopped after reaching the per-source limit#{" of #{limit}" if limit}"
        end

        other_failures = result.failure_details.except(:rate_limited)
        if other_failures.values.sum.positive?
          skipped = other_failures.map do |status, count|
            label_key = status.to_s.tr("_", " ")
            "#{pluralize(count, label_key)}"
          end.join(", ")
          parts << "Skipped #{skipped}"
        end

        if parts.empty?
          parts << "No new scrapes were queued from the #{label}"
        end

        { flash_key: :notice, message: parts.join(". ") + ".", level: :warning }
      end

      def build_error_payload
        message = result.messages.presence&.first ||
          "No items were queued because nothing matched the selected scope."

        { flash_key: :alert, message:, level: :error }
      end
    end
  end
end
