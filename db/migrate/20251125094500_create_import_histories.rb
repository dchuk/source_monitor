# frozen_string_literal: true

class CreateImportHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :"#{SourceMonitor.table_name_prefix}import_histories" do |t|
      t.references :user, null: false, foreign_key: true
      t.jsonb :imported_sources, null: false, default: []
      t.jsonb :failed_sources, null: false, default: []
      t.jsonb :skipped_duplicates, null: false, default: []
      t.jsonb :bulk_settings, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :"#{SourceMonitor.table_name_prefix}import_histories", :created_at
  end
end
