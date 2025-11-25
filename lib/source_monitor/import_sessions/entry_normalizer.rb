# frozen_string_literal: true

module SourceMonitor
  module ImportSessions
    module EntryNormalizer
      module_function

      def normalize(entry)
        entry = entry.to_h

        {
          id: string_for(entry[:id] || entry["id"] || entry[:feed_url] || entry["feed_url"]),
          feed_url: entry[:feed_url].presence || entry["feed_url"].presence,
          title: entry[:title].presence || entry["title"].presence,
          website_url: entry[:website_url].presence || entry["website_url"].presence,
          status: entry[:status].presence || entry["status"].presence || "valid",
          error: entry[:error].presence || entry["error"].presence,
          raw_outline_index: entry[:raw_outline_index] || entry["raw_outline_index"],
          health_status: entry[:health_status].presence || entry["health_status"].presence,
          health_error: entry[:health_error].presence || entry["health_error"].presence
        }
      end

      def string_for(value)
        value&.to_s
      end
      private_class_method :string_for
    end
  end
end
