# frozen_string_literal: true

namespace :source_monitor do
  namespace :maintenance do
    desc "Spread due sources' next_fetch_at across a time window to break thundering herd"
    task stagger_fetch_times: :environment do
      window_minutes = (ENV["WINDOW_MINUTES"] || 10).to_i
      window_seconds = window_minutes * 60.0

      sources = SourceMonitor::Source
        .active
        .where(fetch_status: %w[idle failed])
        .where(
          SourceMonitor::Source.arel_table[:next_fetch_at].eq(nil).or(
            SourceMonitor::Source.arel_table[:next_fetch_at].lteq(Time.current)
          )
        )
        .order(:id)

      count = sources.count

      if count.zero?
        puts "No sources need staggering."
      else
        now = Time.current
        step = count > 1 ? window_seconds / (count - 1).to_f : 0.0

        sources.find_each.with_index do |source, index|
          offset = step * index
          source.update_columns(next_fetch_at: now + offset)
        end

        puts "Staggered #{count} sources across #{window_minutes} minutes."
      end
    end
  end
end
