# frozen_string_literal: true

class RefreshFetchStatusConstraint < ActiveRecord::Migration[8.0]
  ALLOWED_STATUSES = %w[idle queued fetching failed invalid].freeze
  PREVIOUS_STATUSES = %w[idle queued fetching failed].freeze

  def up
    replace_constraint(ALLOWED_STATUSES)
  end

  def down
    replace_constraint(PREVIOUS_STATUSES)
  end

  private

  def replace_constraint(statuses)
    quoted_values = statuses.map { |status| ActiveRecord::Base.connection.quote(status) }.join(", ")

    execute <<~SQL
      ALTER TABLE sourcemon_sources
      DROP CONSTRAINT IF EXISTS check_fetch_status_values
    SQL

    execute <<~SQL
      ALTER TABLE sourcemon_sources
      ADD CONSTRAINT check_fetch_status_values
      CHECK (fetch_status IN (#{quoted_values}))
    SQL
  end
end
