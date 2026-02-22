# frozen_string_literal: true

class AddWordCountsToItemContents < ActiveRecord::Migration[8.0]
  def change
    add_column :sourcemon_item_contents, :scraped_word_count, :integer
    add_column :sourcemon_item_contents, :feed_word_count, :integer
  end
end
