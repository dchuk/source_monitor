# frozen_string_literal: true

module SourceMonitor
  module Dashboard
    module RecentActivity
      Event = Struct.new(
        :type,
        :id,
        :occurred_at,
        :success,
        :items_created,
        :items_updated,
        :scraper_adapter,
        :item_title,
        :item_url,
        :source_name,
        :source_id,
        :source_feed_url,
        keyword_init: true
      ) do
        def type
          self[:type]&.to_sym
        end

        def success?
          !!self[:success]
        end
      end
    end
  end
end
