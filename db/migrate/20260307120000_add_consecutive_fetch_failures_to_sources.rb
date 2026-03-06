# frozen_string_literal: true

class AddConsecutiveFetchFailuresToSources < ActiveRecord::Migration[8.0]
  def change
    add_column :sourcemon_sources, :consecutive_fetch_failures, :integer, default: 0, null: false

    add_index :sourcemon_sources, :consecutive_fetch_failures,
              where: "consecutive_fetch_failures > 0",
              name: "index_sources_on_consecutive_failures"
  end
end
