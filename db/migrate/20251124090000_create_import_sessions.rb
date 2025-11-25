# frozen_string_literal: true

class CreateImportSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :"#{SourceMonitor.table_name_prefix}import_sessions" do |t|
      t.references :user, null: false, foreign_key: true, type: :integer
      t.jsonb :opml_file_metadata, null: false, default: {}
      t.jsonb :parsed_sources, null: false, default: []
      t.jsonb :selected_source_ids, null: false, default: []
      t.jsonb :bulk_settings, null: false, default: {}
      t.string :current_step, null: false

      t.timestamps
    end

    add_index :"#{SourceMonitor.table_name_prefix}import_sessions", :current_step
  end
end
