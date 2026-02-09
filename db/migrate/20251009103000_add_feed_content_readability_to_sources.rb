# frozen_string_literal: true

class AddFeedContentReadabilityToSources < ActiveRecord::Migration[8.0]
  def change
    add_column :sourcemon_sources, :feed_content_readability_enabled, :boolean, default: false, null: false
  end
end
