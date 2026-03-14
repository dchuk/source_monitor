# frozen_string_literal: true

class AddCompositeIndexesToLogTables < ActiveRecord::Migration[8.0]
  def change
    add_index :sourcemon_fetch_logs, [ :source_id, :started_at ],
              name: "index_fetch_logs_on_source_id_and_started_at"
    add_index :sourcemon_scrape_logs, [ :source_id, :started_at ],
              name: "index_scrape_logs_on_source_id_and_started_at"
    add_index :sourcemon_scrape_logs, [ :item_id, :started_at ],
              name: "index_scrape_logs_on_item_id_and_started_at"
    add_index :sourcemon_health_check_logs, [ :source_id, :started_at ],
              name: "index_health_check_logs_on_source_id_and_started_at"
  end
end
