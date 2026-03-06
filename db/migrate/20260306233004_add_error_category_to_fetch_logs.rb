# frozen_string_literal: true

class AddErrorCategoryToFetchLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :sourcemon_fetch_logs, :error_category, :string
    add_index :sourcemon_fetch_logs, :error_category
  end
end
