# frozen_string_literal: true

class AddDismissedAtToImportHistories < ActiveRecord::Migration[8.1]
  def change
    add_column :"#{SourceMonitor.table_name_prefix}import_histories", :dismissed_at, :datetime
  end
end
