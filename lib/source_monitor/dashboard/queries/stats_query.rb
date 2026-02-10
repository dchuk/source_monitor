# frozen_string_literal: true

module SourceMonitor
  module Dashboard
    class Queries
      class StatsQuery
        def initialize(reference_time:)
          @reference_time = reference_time
        end

        def call
          {
            total_sources: integer_value(source_counts["total_sources"]),
            active_sources: integer_value(source_counts["active_sources"]),
            failed_sources: integer_value(source_counts["failed_sources"]),
            total_items: total_items_count,
            fetches_today: fetches_today_count
          }
        end

        private

        attr_reader :reference_time

        def source_counts
          @source_counts ||= begin
            SourceMonitor::Source.connection.exec_query(source_counts_sql).first || {}
          end
        end

        def total_items_count
          SourceMonitor::Item.connection.select_value(total_items_sql).to_i
        end

        def fetches_today_count
          SourceMonitor::FetchLog.where("started_at >= ?", start_of_day).count
        end

        def source_counts_sql
          <<~SQL.squish
            SELECT
              COUNT(*) AS total_sources,
              SUM(CASE WHEN active THEN 1 ELSE 0 END) AS active_sources,
              SUM(CASE WHEN (#{failure_condition}) THEN 1 ELSE 0 END) AS failed_sources
            FROM #{SourceMonitor::Source.quoted_table_name}
          SQL
        end

        def failure_condition
          [
            "#{SourceMonitor::Source.quoted_table_name}.failure_count > 0",
            "#{SourceMonitor::Source.quoted_table_name}.last_error IS NOT NULL",
            "#{SourceMonitor::Source.quoted_table_name}.last_error_at IS NOT NULL"
          ].join(" OR ")
        end

        def total_items_sql
          "SELECT COUNT(*) FROM #{SourceMonitor::Item.quoted_table_name}"
        end

        def start_of_day
          reference_time.in_time_zone.beginning_of_day
        end

        def integer_value(value)
          value.to_i
        end
      end
    end
  end
end
