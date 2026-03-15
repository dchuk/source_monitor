# frozen_string_literal: true

class AlignHealthStatusDefault < ActiveRecord::Migration[8.1]
  def up
    change_column_default :sourcemon_sources, :health_status, from: "healthy", to: "working"
  end

  def down
    change_column_default :sourcemon_sources, :health_status, from: "working", to: "healthy"
  end
end
