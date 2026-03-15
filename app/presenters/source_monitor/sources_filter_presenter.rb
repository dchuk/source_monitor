# frozen_string_literal: true

module SourceMonitor
  # Encapsulates filter state logic for the sources index view.
  # Extracts filter detection, label generation, and active-filter
  # tracking from the template into a testable object.
  class SourcesFilterPresenter
    DROPDOWN_FILTER_KEYS = %w[
      active_eq
      health_status_eq
      feed_format_eq
      scraper_adapter_eq
      scraping_enabled_eq
      avg_feed_words_lt
    ].freeze

    attr_reader :search_params, :search_term, :fetch_interval_filter, :adapter_options

    # @param search_params [Hash] sanitized Ransack search params
    # @param search_term [String] current text search term
    # @param fetch_interval_filter [Hash, nil] active fetch interval filter
    # @param adapter_options [Array<String>] distinct scraper adapter values
    def initialize(search_params:, search_term:, fetch_interval_filter:, adapter_options: [])
      @search_params = search_params || {}
      @search_term = search_term.to_s
      @fetch_interval_filter = fetch_interval_filter
      @adapter_options = adapter_options
    end

    def has_any_filter?
      @search_term.present? || @fetch_interval_filter.present? || active_filter_keys.any?
    end

    # Returns the subset of DROPDOWN_FILTER_KEYS that have present values
    def active_filter_keys
      DROPDOWN_FILTER_KEYS.select { |k| @search_params[k].present? }
    end

    # Returns a hash mapping active filter keys to human-readable labels
    def filter_labels
      {
        "active_eq" => status_label,
        "health_status_eq" => "Health: #{@search_params['health_status_eq']&.titleize}",
        "feed_format_eq" => "Format: #{@search_params['feed_format_eq']&.upcase}",
        "scraper_adapter_eq" => "Adapter: #{@search_params['scraper_adapter_eq']&.titleize}",
        "scraping_enabled_eq" => scraping_label,
        "avg_feed_words_lt" => "Avg Feed Words: < #{@search_params['avg_feed_words_lt']}"
      }
    end

    private

    def status_label
      @search_params["active_eq"] == "true" ? "Status: Active" : "Status: Paused"
    end

    def scraping_label
      @search_params["scraping_enabled_eq"] == "true" ? "Scraping: Enabled" : "Scraping: Disabled"
    end
  end
end
