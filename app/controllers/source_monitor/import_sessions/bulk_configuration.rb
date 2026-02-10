# frozen_string_literal: true

module SourceMonitor
  module ImportSessions
    module BulkConfiguration
      extend ActiveSupport::Concern

      private

      def build_bulk_source_from_session
        settings = @import_session.bulk_settings.presence || {}
        build_bulk_source(settings)
      end

      def build_bulk_source_from_params
        settings = configure_source_params
        settings = strip_identity_attributes(settings) if settings
        settings ||= @import_session.bulk_settings.presence || {}

        build_bulk_source(settings)
      end

      def build_bulk_source(settings)
        sample_identity = sample_identity_attributes
        defaults = SourceMonitor::Sources::Params.default_attributes

        source = SourceMonitor::Source.new(defaults.merge(sample_identity))
        source.assign_attributes(settings.deep_symbolize_keys) if settings.present?
        source
      end

      def sample_identity_attributes
        entry = selected_entries_for_identity.first
        return fallback_identity unless entry

        normalized = normalize_entry(entry)
        {
          name: normalized[:title].presence || normalized[:feed_url] || fallback_identity[:name],
          feed_url: normalized[:feed_url].presence || fallback_identity[:feed_url],
          website_url: normalized[:website_url]
        }
      end

      def selected_entries_for_identity
        targets = Array(@import_session.selected_source_ids).map(&:to_s)
        entries = Array(@import_session.parsed_sources)
        return entries if targets.blank?

        entries.select { |entry| targets.include?(entry.to_h.fetch("id", entry[:id]).to_s) }
      end

      def fallback_identity
        {
          name: "Imported source",
          feed_url: "https://example.com/feed.xml"
        }
      end

      def configure_source_params
        return unless params[:source].present?

        SourceMonitor::Sources::Params.sanitize(params)
      end

      def strip_identity_attributes(settings)
        settings.with_indifferent_access.except(:name, :feed_url, :website_url)
      end

      def persist_bulk_settings_if_valid!
        settings = configure_source_params
        return unless settings
        return unless @bulk_source.valid?

        @import_session.update!(bulk_settings: bulk_settings_payload(@bulk_source))
      end

      def bulk_settings_payload(source)
        payload = source.attributes.slice(*bulk_setting_keys)
        payload["scrape_settings"] = source.scrape_settings

        SourceMonitor::Security::ParameterSanitizer.sanitize(payload)
      end

      def bulk_setting_keys
        %w[
          fetch_interval_minutes
          active
          auto_scrape
          scraping_enabled
          requires_javascript
          feed_content_readability_enabled
          scraper_adapter
          items_retention_days
          max_items
          adaptive_fetching_enabled
          health_auto_pause_threshold
          scrape_settings
        ]
      end

      def prepare_configure_context
        @bulk_source = build_bulk_source_from_session
      end
    end
  end
end
