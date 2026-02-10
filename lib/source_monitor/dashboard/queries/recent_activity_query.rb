# frozen_string_literal: true

module SourceMonitor
  module Dashboard
    class Queries
      class RecentActivityQuery
        EVENT_TYPE_FETCH = "fetch_log"
        EVENT_TYPE_SCRAPE = "scrape_log"
        EVENT_TYPE_ITEM = "item"

        def initialize(limit:)
          @limit = limit
        end

        def call
          rows = connection.exec_query(sanitized_sql)
          rows.map { |row| build_event(row) }
        end

        private

        attr_reader :limit

        def connection
          ActiveRecord::Base.connection
        end

        def build_event(row)
          SourceMonitor::Dashboard::RecentActivity::Event.new(
            type: row["resource_type"].to_sym,
            id: row["resource_id"],
            occurred_at: row["occurred_at"],
            success: row["success_flag"].to_i == 1,
            items_created: row["items_created"],
            items_updated: row["items_updated"],
            scraper_adapter: row["scraper_adapter"],
            item_title: row["item_title"],
            item_url: row["item_url"],
            source_name: row["source_name"],
            source_id: row["source_id"]
          )
        end

        def sanitized_sql
          ActiveRecord::Base.send(:sanitize_sql_array, [ unified_sql_template, limit ])
        end

        def unified_sql_template
          <<~SQL
            SELECT resource_type,
                   resource_id,
                   occurred_at,
                   success_flag,
                   items_created,
                   items_updated,
                   scraper_adapter,
                   item_title,
                   item_url,
                   source_name,
                   source_id
            FROM (
              #{fetch_log_sql}
              UNION ALL
              #{scrape_log_sql}
              UNION ALL
              #{item_sql}
            ) AS dashboard_events
            WHERE occurred_at IS NOT NULL
            ORDER BY occurred_at DESC
            LIMIT ?
          SQL
        end

        def fetch_log_sql
          <<~SQL
            SELECT
              '#{EVENT_TYPE_FETCH}' AS resource_type,
              #{SourceMonitor::FetchLog.quoted_table_name}.id AS resource_id,
              #{SourceMonitor::FetchLog.quoted_table_name}.started_at AS occurred_at,
              CASE WHEN #{SourceMonitor::FetchLog.quoted_table_name}.success THEN 1 ELSE 0 END AS success_flag,
              #{SourceMonitor::FetchLog.quoted_table_name}.items_created AS items_created,
              #{SourceMonitor::FetchLog.quoted_table_name}.items_updated AS items_updated,
              NULL AS scraper_adapter,
              NULL AS item_title,
              NULL AS item_url,
              NULL AS source_name,
              #{SourceMonitor::FetchLog.quoted_table_name}.source_id AS source_id
            FROM #{SourceMonitor::FetchLog.quoted_table_name}
          SQL
        end

        def scrape_log_sql
          <<~SQL
            SELECT
              '#{EVENT_TYPE_SCRAPE}' AS resource_type,
              #{SourceMonitor::ScrapeLog.quoted_table_name}.id AS resource_id,
              #{SourceMonitor::ScrapeLog.quoted_table_name}.started_at AS occurred_at,
              CASE WHEN #{SourceMonitor::ScrapeLog.quoted_table_name}.success THEN 1 ELSE 0 END AS success_flag,
              NULL AS items_created,
              NULL AS items_updated,
              #{SourceMonitor::ScrapeLog.quoted_table_name}.scraper_adapter AS scraper_adapter,
              NULL AS item_title,
              NULL AS item_url,
              #{SourceMonitor::Source.quoted_table_name}.#{quoted_source_name} AS source_name,
              #{SourceMonitor::ScrapeLog.quoted_table_name}.source_id AS source_id
            FROM #{SourceMonitor::ScrapeLog.quoted_table_name}
            LEFT JOIN #{SourceMonitor::Source.quoted_table_name}
              ON #{SourceMonitor::Source.quoted_table_name}.id = #{SourceMonitor::ScrapeLog.quoted_table_name}.source_id
          SQL
        end

        def item_sql
          <<~SQL
            SELECT
              '#{EVENT_TYPE_ITEM}' AS resource_type,
              #{SourceMonitor::Item.quoted_table_name}.id AS resource_id,
              #{SourceMonitor::Item.quoted_table_name}.created_at AS occurred_at,
              1 AS success_flag,
              NULL AS items_created,
              NULL AS items_updated,
              NULL AS scraper_adapter,
              #{SourceMonitor::Item.quoted_table_name}.title AS item_title,
              #{SourceMonitor::Item.quoted_table_name}.url AS item_url,
              #{SourceMonitor::Source.quoted_table_name}.#{quoted_source_name} AS source_name,
              #{SourceMonitor::Item.quoted_table_name}.source_id AS source_id
            FROM #{SourceMonitor::Item.quoted_table_name}
            LEFT JOIN #{SourceMonitor::Source.quoted_table_name}
              ON #{SourceMonitor::Source.quoted_table_name}.id = #{SourceMonitor::Item.quoted_table_name}.source_id
          SQL
        end

        def quoted_source_name
          ActiveRecord::Base.connection.quote_column_name("name")
        end
      end
    end
  end
end
