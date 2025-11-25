# frozen_string_literal: true

class AddHealthFieldsToImportSessions < ActiveRecord::Migration[8.1]
  def change
    change_table :"#{SourceMonitor.table_name_prefix}import_sessions" do |t|
      t.boolean :health_checks_active, null: false, default: false
      t.jsonb :health_check_target_ids, null: false, default: []
      t.datetime :health_check_started_at
      t.datetime :health_check_completed_at
    end

    add_index :"#{SourceMonitor.table_name_prefix}import_sessions", :health_checks_active
  end
end
