# frozen_string_literal: true

class AddMinScrapeIntervalToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sourcemon_sources, :min_scrape_interval, :decimal, precision: 10, scale: 2, null: true, default: nil
  end
end
