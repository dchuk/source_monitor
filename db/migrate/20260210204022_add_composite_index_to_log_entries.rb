# frozen_string_literal: true

class AddCompositeIndexToLogEntries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :sourcemon_log_entries, [:started_at, :id],
              order: { started_at: :desc, id: :desc },
              name: "index_log_entries_on_started_at_desc_id_desc",
              algorithm: :concurrently

    add_index :sourcemon_log_entries, [:loggable_type, :started_at, :id],
              order: { started_at: :desc, id: :desc },
              name: "index_log_entries_on_loggable_type_started_at_id",
              algorithm: :concurrently
  end
end
