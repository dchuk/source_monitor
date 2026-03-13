# frozen_string_literal: true

require "source_monitor/pagination/paginator"

module SourceMonitor
  module Dashboard
    class UpcomingFetchSchedule
      Group = Struct.new(
        :key,
        :label,
        :min_minutes,
        :max_minutes,
        :window_start,
        :window_end,
        :include_unscheduled,
        :sources,
        :page,
        :has_next_page,
        :has_previous_page,
        keyword_init: true
      ) do
        def empty?
          sources.blank?
        end
      end

      INTERVAL_DEFINITIONS = [
        { key: "0-30", label: "Within 30 minutes", min_minutes: 0, max_minutes: 30 },
        { key: "30-60", label: "30-60 minutes", min_minutes: 30, max_minutes: 60 },
        { key: "60-120", label: "60-120 minutes", min_minutes: 60, max_minutes: 120 },
        { key: "120-240", label: "120-240 minutes", min_minutes: 120, max_minutes: 240 },
        { key: "240+", label: "240 minutes +", min_minutes: 240, max_minutes: nil, include_unscheduled: true }
      ].freeze

      DEFAULT_PER_PAGE = 10

      attr_reader :scope, :reference_time

      def initialize(scope: SourceMonitor::Source.active, reference_time: Time.current, pages: {}, per_page: DEFAULT_PER_PAGE)
        @scope = scope
        @reference_time = reference_time
        @pages = pages
        @per_page = per_page
      end

      def groups
        @groups ||= build_groups
      end

      private

      attr_reader :pages, :per_page

      def build_groups
        INTERVAL_DEFINITIONS.filter_map do |definition|
          bucket_scope = scope_for_bucket(definition)
          next unless bucket_scope.exists?

          page_number = pages.fetch(definition[:key], 1).to_i
          page_number = 1 if page_number < 1

          result = SourceMonitor::Pagination::Paginator.new(
            scope: bucket_scope.order(:next_fetch_at, :name),
            page: page_number,
            per_page: per_page
          ).paginate

          Group.new(
            key: definition[:key],
            label: definition[:label],
            min_minutes: definition[:min_minutes],
            max_minutes: definition[:max_minutes],
            window_start: window_start_for(definition[:min_minutes]),
            window_end: window_end_for(definition[:max_minutes]),
            include_unscheduled: definition[:include_unscheduled],
            sources: result.records,
            page: result.page,
            has_next_page: result.has_next_page,
            has_previous_page: result.has_previous_page
          )
        end
      end

      def scope_for_bucket(definition)
        window_start = reference_time + definition[:min_minutes].minutes
        max_minutes = definition[:max_minutes]

        if max_minutes.nil?
          # Last bucket: 240+ minutes OR unscheduled (nil next_fetch_at)
          scheduled = scope.where(next_fetch_at: window_start..)
          unscheduled = scope.where(next_fetch_at: nil)
          scheduled.or(unscheduled)
        else
          window_end = reference_time + max_minutes.minutes
          scope.where(next_fetch_at: window_start...window_end)
        end
      end

      def window_start_for(min_minutes)
        return nil if min_minutes.nil?

        reference_time + min_minutes.minutes
      end

      def window_end_for(max_minutes)
        return nil if max_minutes.nil?

        reference_time + max_minutes.minutes
      end
    end
  end
end
