# frozen_string_literal: true

module SourceMonitor
  module ImportSessions
    module EntryAnnotation
      extend ActiveSupport::Concern

      private

      def annotated_entries(selected_ids)
        selected_ids ||= []
        entries = Array(@import_session.parsed_sources)
        return [] if entries.blank?

        normalized = entries.map { |entry| normalize_entry(entry) }

        feed_urls = normalized.filter_map { |entry| entry[:feed_url]&.downcase }
        duplicate_lookup = if feed_urls.present?
          SourceMonitor::Source.where("LOWER(feed_url) IN (?)", feed_urls).pluck(:feed_url).map(&:downcase)
        else
          []
        end

        normalized.map do |entry|
          duplicate = entry[:feed_url].present? && duplicate_lookup.include?(entry[:feed_url].downcase)
          entry.merge(
            duplicate: duplicate,
            selectable: entry[:status] == "valid" && !duplicate,
            selected: selected_ids.include?(entry[:id])
          )
        end
      end

      def normalize_entry(entry)
        entry = entry.to_h
        SourceMonitor::ImportSessions::EntryNormalizer.normalize(entry)
      end

      def filter_entries(entries, filter)
        case filter
        when "new"
          entries.select { |entry| entry[:selectable] }
        when "existing"
          entries.select { |entry| entry[:duplicate] }
        else
          entries
        end
      end

      def selectable_entries_from(entries)
        entries.select { |entry| entry[:selectable] }
      end

      def selectable_entries
        @selectable_entries ||= annotated_entries(@selected_source_ids).select { |entry| entry[:selectable] }
      end

      def build_selection_from_params
        @selected_source_ids ||= []

        if params.dig(:import_session, :select_all) == "true"
          return selectable_entries.map { |entry| entry[:id] }
        end

        if params.dig(:import_session, :select_none) == "true"
          return []
        end

        ids = params.dig(:import_session, :selected_source_ids)
        return [] unless ids

        Array(ids).map { |id| id.to_s }.uniq
      end

      def health_check_selection_from_params
        if params.dig(:import_session, :select_all) == "true"
          return health_check_targets.dup
        end

        return [] if params.dig(:import_session, :select_none) == "true"

        ids = params.dig(:import_session, :selected_source_ids)
        return Array(@import_session.selected_source_ids).map(&:to_s) unless ids

        Array(ids).map { |id| id.to_s }.uniq & health_check_targets
      end

      def advancing_from_health_check?
        target_step != "health_check"
      end

      def advancing_from_preview?
        target_step != "preview"
      end

      def normalize_page_param(value)
        number = value.to_i
        number = 1 if number <= 0
        number
      rescue StandardError
        1
      end

      def permitted_filter(raw)
        value = raw.to_s.presence
        return unless value

        %w[all new existing].find { |candidate| candidate == value }
      end

      def preview_per_page
        25
      end

      def state_params
        @state_params ||= begin
          permitted = params.fetch(:import_session, {}).permit(
            :current_step,
            :next_step,
            :select_all,
            :select_none,
            parsed_sources: [],
            selected_source_ids: [],
            bulk_settings: {},
            opml_file_metadata: {}
          )

          SourceMonitor::Security::ParameterSanitizer.sanitize(permitted.to_h)
        end
      end

      def permitted_step(value)
        step = value.to_s.presence
        return unless step

        ImportSession::STEP_ORDER.find { |candidate| candidate == step }
      end

      def target_step
        next_step = state_params[:next_step] || state_params["next_step"]
        permitted_step(next_step) || @current_step || ImportSession.default_step
      end

      def session_attributes
        attrs = state_params.except(:next_step, :current_step, "next_step", "current_step")
        attrs[:opml_file_metadata] = build_file_metadata if uploading_file?
        attrs[:current_step] = target_step
        attrs
      end

      def prepare_preview_context(skip_default: false)
        @filter = permitted_filter(params[:filter]) || "all"
        @page = normalize_page_param(params[:page])
        @selected_source_ids = Array(@import_session.selected_source_ids).map(&:to_s)

        @preview_entries = annotated_entries(@selected_source_ids)

        if !skip_default && @selected_source_ids.blank? && @preview_entries.present?
          defaults = selectable_entries_from(@preview_entries).map { |entry| entry[:id] }
          @selected_source_ids = defaults
          @import_session.update_column(:selected_source_ids, defaults)
          @preview_entries = annotated_entries(@selected_source_ids)
        end

        @filtered_entries = filter_entries(@preview_entries, @filter)

        paginator = SourceMonitor::Pagination::Paginator.new(
          scope: @filtered_entries,
          page: @page,
          per_page: preview_per_page
        ).paginate

        @paginated_entries = paginator.records
        @has_next_page = paginator.has_next_page
        @has_previous_page = paginator.has_previous_page
        @page = paginator.page
      end

      def prepare_confirm_context
        @selected_source_ids = Array(@import_session.selected_source_ids).map(&:to_s)
        @selected_entries = annotated_entries(@selected_source_ids)
          .select { |entry| @selected_source_ids.include?(entry[:id]) }
        @bulk_settings = @import_session.bulk_settings || {}
      end
    end
  end
end
