# frozen_string_literal: true

module SourceMonitor
  module Sources
    module Params
      module_function

      def permitted_attributes
        [
          :name,
          :feed_url,
          :website_url,
          :fetch_interval_minutes,
          :active,
          :auto_scrape,
          :scraping_enabled,
          :requires_javascript,
          :feed_content_readability_enabled,
          :scraper_adapter,
          :items_retention_days,
          :max_items,
          :adaptive_fetching_enabled,
          :health_auto_pause_threshold,
          { scrape_settings: [
            :include_plain_text,
            :timeout,
            :javascript_enabled,
            { selectors: %i[content title], http: [], readability: [] }
          ] }
        ]
      end

      def default_attributes
        {
          active: true,
          scraping_enabled: false,
          auto_scrape: false,
          requires_javascript: false,
          feed_content_readability_enabled: false,
          fetch_interval_minutes: 360,
          adaptive_fetching_enabled: true,
          scraper_adapter: "readability"
        }
      end

      def sanitize(params)
        permitted = params.require(:source).permit(*permitted_attributes)
        SourceMonitor::Security::ParameterSanitizer.sanitize(permitted.to_h)
      end
    end
  end
end
