# frozen_string_literal: true

class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Index for activity rate calculations
    # Query: SELECT COUNT(*) FROM items WHERE source_id IN (...) AND created_at >= ? GROUP BY source_id
    unless index_exists?(:sourcemon_items, [ :source_id, :created_at ], name: "index_items_on_source_and_created_at_for_rates")
      add_index :sourcemon_items,
        [ :source_id, :created_at ],
        name: "index_items_on_source_and_created_at_for_rates"
    end

    # Partial index for due_for_fetch queries
    # Query: SELECT * FROM sources WHERE active = true AND (next_fetch_at IS NULL OR next_fetch_at <= ?)
    unless index_exists?(:sourcemon_sources, [ :active, :next_fetch_at ], name: "index_sources_on_active_and_next_fetch")
      add_index :sourcemon_sources,
        [ :active, :next_fetch_at ],
        where: "active = true",
        name: "index_sources_on_active_and_next_fetch"
    end

    # Partial index for failed source queries
    # Query: SELECT * FROM sources WHERE failure_count > 0
    unless index_exists?(:sourcemon_sources, :failure_count, name: "index_sources_on_failures")
      add_index :sourcemon_sources,
        :failure_count,
        where: "failure_count > 0",
        name: "index_sources_on_failures"
    end
  end
end
