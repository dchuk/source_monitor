# frozen_string_literal: true

module SourceMonitor
  class SourceDetailsPresenter < BasePresenter
    DATE_FORMAT = "%b %d, %Y %H:%M %Z"

    def fetch_interval_display
      hours = number_with_precision(fetch_interval_minutes / 60.0, precision: 2)
      "#{fetch_interval_minutes} minutes (~#{hours} hours)"
    end

    def circuit_state_label
      if fetch_circuit_open?
        until_time = fetch_circuit_until&.strftime(DATE_FORMAT) || "unknown"
        "Open until #{until_time}"
      else
        "Closed"
      end
    end

    def adaptive_interval_label
      adaptive_fetching_enabled? ? "Auto" : "Fixed"
    end

    def formatted_next_fetch_at
      format_timestamp(next_fetch_at)
    end

    def formatted_last_fetched_at
      format_timestamp(last_fetched_at)
    end

    def details_hash
      {
        "Fetch interval" => fetch_interval_display,
        "Adaptive interval" => adaptive_interval_label,
        "Scraper" => scraper_adapter,
        "Feed content" => feed_content_readability_enabled? ? "Readability" : "Raw",
        "Active" => active? ? "Yes" : "No",
        "Scraping" => scraping_enabled? ? "Enabled" : "Disabled",
        "Auto scrape" => auto_scrape? ? "Enabled" : "Disabled",
        "Requires JS" => requires_javascript? ? "Yes" : "No",
        "Failure count" => failure_count,
        "Retry attempt" => fetch_retry_attempt,
        "Circuit state" => circuit_state_label,
        "Last error" => last_error.presence || "None",
        "Items count" => items_count,
        "Retention days" => items_retention_days || "\u2014",
        "Max items" => max_items || "\u2014"
      }
    end

    private

    def format_timestamp(time)
      return "\u2014" if time.nil?

      time.strftime(DATE_FORMAT)
    end
  end
end
