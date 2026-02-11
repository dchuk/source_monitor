# frozen_string_literal: true

module SourceMonitor
  module ImportSessions
    module HealthCheckManagement
      extend ActiveSupport::Concern

      private

      def start_health_checks_if_needed
        return unless @current_step == "health_check"

        jobs_to_enqueue = []

        @import_session.with_lock do
          @import_session.reload
          selected = Array(@import_session.selected_source_ids).map(&:to_s)

          if selected.blank?
            @import_session.update_columns(health_checks_active: false, health_check_target_ids: [])
            next
          end

          if @import_session.health_checks_active? && @import_session.health_check_targets.sort == selected.sort
            @health_check_target_ids = @import_session.health_check_targets
            next
          end

          updated_entries = reset_health_results(@import_session.parsed_sources, selected)
          @import_session.update!(
            parsed_sources: updated_entries,
            health_checks_active: true,
            health_check_target_ids: selected,
            health_check_started_at: Time.current,
            health_check_completed_at: nil
          )

          @health_check_target_ids = selected
          jobs_to_enqueue = selected
        end

        enqueue_health_check_jobs(@import_session, jobs_to_enqueue) if jobs_to_enqueue.any?
      end

      def reset_health_results(entries, target_ids)
        Array(entries).map do |entry|
          entry_hash = entry.to_h
          entry_id = entry_hash["id"] || entry_hash[:id]
          next entry_hash unless target_ids.include?(entry_id.to_s)

          entry_hash.merge("health_status" => "pending", "health_error" => nil)
        end
      end

      def enqueue_health_check_jobs(import_session, target_ids)
        target_ids.each do |target_id|
          SourceMonitor::ImportSessionHealthCheckJob.set(wait: 1.second).perform_later(import_session.id, target_id)
        end
      end

      def deactivate_health_checks!
        return unless @import_session.health_checks_active?

        @import_session.update_columns(
          health_checks_active: false,
          health_check_completed_at: Time.current
        )
      end

      def health_check_entries(selected_ids)
        targets = health_check_targets
        entries = Array(@import_session.parsed_sources).map { |entry| normalize_entry(entry) }

        entries.select { |entry| targets.include?(entry[:id]) }.map do |entry|
          entry.merge(selected: selected_ids.include?(entry[:id]))
        end
      end

      def health_check_progress(entries)
        total = health_check_targets.size
        completed = entries.count { |entry| health_check_complete?(entry) }

        {
          completed: completed,
          total: total,
          pending: [ total - completed, 0 ].max,
          active: @import_session.health_checks_active?,
          done: total.positive? && completed >= total
        }
      end

      def health_check_complete?(entry)
        %w[healthy unhealthy].include?(entry[:health_status].to_s)
      end

      def health_check_targets
        targets = @import_session.health_check_targets
        targets = Array(@import_session.selected_source_ids).map(&:to_s) if targets.blank?
        targets
      end

      def prepare_health_check_context
        start_health_checks_if_needed

        @selected_source_ids = Array(@import_session.selected_source_ids).map(&:to_s)
        @health_check_entries = health_check_entries(@selected_source_ids)
        @health_check_target_ids = health_check_targets
        @health_progress = health_check_progress(@health_check_entries)
      end
    end
  end
end
