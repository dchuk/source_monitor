# frozen_string_literal: true

class AddFetchStatusCheckConstraint < ActiveRecord::Migration[8.0]
  def up
    # Add PostgreSQL CHECK constraint to enforce fetch_status enum values at database level
    # This complements the application-level validation in the Source model
    execute <<-SQL
      ALTER TABLE sourcemon_sources
      ADD CONSTRAINT check_fetch_status_values
      CHECK (fetch_status IN ('idle', 'queued', 'fetching', 'failed'))
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE sourcemon_sources
      DROP CONSTRAINT check_fetch_status_values
    SQL
  end
end
