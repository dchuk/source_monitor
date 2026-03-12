class SimplifyHealthStatusValues < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE sourcemon_sources SET health_status = 'working' WHERE health_status IN ('healthy', 'auto_paused', 'unknown')
    SQL
    execute <<~SQL
      UPDATE sourcemon_sources SET health_status = 'failing' WHERE health_status IN ('warning', 'critical')
    SQL
    # 'declining' and 'improving' remain unchanged
  end

  def down
    execute <<~SQL
      UPDATE sourcemon_sources SET health_status = 'healthy' WHERE health_status = 'working'
    SQL
    execute <<~SQL
      UPDATE sourcemon_sources SET health_status = 'critical' WHERE health_status = 'failing'
    SQL
  end
end
