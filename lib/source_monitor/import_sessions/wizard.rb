# frozen_string_literal: true

require "nokogiri"
require "uri"
require "active_support/core_ext/object/blank"
require "source_monitor/import_sessions/entry_normalizer"

module SourceMonitor
  module ImportSessions
    class Wizard
      ALLOWED_CONTENT_TYPES = %w[text/xml application/xml text/x-opml application/opml].freeze
      GENERIC_CONTENT_TYPES = %w[application/octet-stream binary/octet-stream].freeze

      class UploadError < StandardError; end

      UploadResult = Struct.new(:status, :errors, :current_step, :preview_context, keyword_init: true)

      PreviewResult = Struct.new(
        :status,
        :selected_source_ids,
        :valid_ids,
        :current_step,
        :selection_error,
        :preview_context,
        keyword_init: true
      ) do
        def blocked?
          status == :blocked
        end
      end

      PreviewContext = Struct.new(
        :filter,
        :page,
        :selected_source_ids,
        :preview_entries,
        :filtered_entries,
        :paginated_entries,
        :has_next_page,
        :has_previous_page,
        keyword_init: true
      )

      def initialize(import_session:, params:, current_step:, now: Time.current)
        @import_session = import_session
        @params = params
        @current_step = current_step
        @now = now
      end

      def handle_upload
        errors = validate_upload
        return UploadResult.new(status: :invalid, errors: errors, current_step: current_step) if errors.any?

        parsed_entries = parse_opml_file(opml_file)
        valid_entries = parsed_entries.select { |entry| entry[:status] == "valid" }

        if valid_entries.empty?
          import_session.update!(
            opml_file_metadata: build_file_metadata,
            parsed_sources: parsed_entries,
            current_step: "upload"
          )

          return UploadResult.new(
            status: :invalid,
            errors: [ "We couldn't find any valid feeds in that OPML file. Check the file and try again." ],
            current_step: "upload"
          )
        end

        next_step = target_step
        import_session.update!(
          opml_file_metadata: build_file_metadata.merge("uploaded_at" => now),
          parsed_sources: parsed_entries,
          current_step: next_step
        )

        UploadResult.new(
          status: :success,
          errors: [],
          current_step: next_step,
          preview_context: preview_context(skip_default: true)
        )
      rescue UploadError => error
        UploadResult.new(status: :invalid, errors: [ error.message ], current_step: current_step)
      end

      def handle_preview
        selected_source_ids = Array(import_session.selected_source_ids).map(&:to_s)
        preview_entries = annotated_entries(selected_source_ids)
        selectable_entries = preview_entries.select { |entry| entry[:selectable] }

        valid_ids = if import_session_params[:select_all].present?
          ids = selectable_entries.map { |entry| entry[:id] }
          import_session.update_column(:selected_source_ids, ids)
          ids
        elsif import_session_params[:select_none].present?
          import_session.update_column(:selected_source_ids, [])
          []
        else
          selected_source_ids = build_selection_from_params(selectable_entries)
          ids = selectable_entries.index_by { |entry| entry[:id] }.slice(*selected_source_ids).keys
          import_session.update!(selected_source_ids: ids)
          ids
        end

        if advancing_from_preview? && valid_ids.empty?
          return PreviewResult.new(
            status: :blocked,
            selected_source_ids: valid_ids,
            valid_ids: valid_ids,
            current_step: current_step,
            selection_error: "Select at least one new source to continue.",
            preview_context: preview_context(skip_default: true, selected_source_ids: valid_ids)
          )
        end

        next_step = target_step
        import_session.update_column(:current_step, next_step) if import_session.current_step != next_step

        PreviewResult.new(
          status: :success,
          selected_source_ids: valid_ids,
          valid_ids: valid_ids,
          current_step: next_step,
          preview_context: preview_context(skip_default: true, selected_source_ids: valid_ids)
        )
      end

      def preview_context(skip_default: false, selected_source_ids: nil)
        filter = permitted_filter(params[:filter]) || "all"
        page = normalize_page_param(params[:page])
        selected_source_ids = Array(selected_source_ids || import_session.selected_source_ids).map(&:to_s)
        preview_entries = annotated_entries(selected_source_ids)

        if !skip_default && selected_source_ids.blank? && preview_entries.present?
          selected_source_ids = preview_entries.select { |entry| entry[:selectable] }.map { |entry| entry[:id] }
          import_session.update_column(:selected_source_ids, selected_source_ids)
          preview_entries = annotated_entries(selected_source_ids)
        end

        filtered_entries = filter_entries(preview_entries, filter)
        paginator = SourceMonitor::Pagination::Paginator.new(
          scope: filtered_entries,
          page: page,
          per_page: preview_per_page
        ).paginate

        PreviewContext.new(
          filter: filter,
          page: paginator.page,
          selected_source_ids: selected_source_ids,
          preview_entries: preview_entries,
          filtered_entries: filtered_entries,
          paginated_entries: paginator.records,
          has_next_page: paginator.has_next_page,
          has_previous_page: paginator.has_previous_page
        )
      end

      private

      attr_reader :import_session, :params, :current_step, :now

      def validate_upload
        return [ "Upload an OPML file to continue." ] unless opml_file.present?

        errors = []
        errors << "The uploaded file is empty. Choose another OPML file." if opml_file.size.to_i <= 0

        if opml_file.content_type.present? && !content_type_allowed?(opml_file.content_type) && !generic_content_type?(opml_file.content_type)
          errors << "Upload must be an OPML or XML file."
        end

        errors
      end

      def opml_file
        params[:opml_file]
      end

      def build_file_metadata
        return {} unless opml_file.respond_to?(:original_filename)

        {
          "filename" => opml_file.original_filename,
          "byte_size" => opml_file.size,
          "content_type" => opml_file.content_type
        }
      end

      def content_type_allowed?(content_type)
        ALLOWED_CONTENT_TYPES.include?(content_type)
      end

      def generic_content_type?(content_type)
        GENERIC_CONTENT_TYPES.include?(content_type)
      end

      def parse_opml_file(file)
        content = file.read
        file.rewind if file.respond_to?(:rewind)

        raise UploadError, "The uploaded file appears to be empty." if content.blank?

        document = Nokogiri::XML(content) { |config| config.strict.nonet }
        raise UploadError, "The uploaded file is not valid XML or OPML." if document.root.nil?

        document.xpath("//outline").each_with_index.filter_map do |outline, index|
          next unless outline.attribute_nodes.any? { |attr| attr.name.casecmp("xmlurl").zero? }

          build_entry(outline, index)
        end
      rescue Nokogiri::XML::SyntaxError => error
        raise UploadError, "We couldn't parse that OPML file: #{error.message}"
      end

      def build_entry(outline, index)
        feed_url = outline_attribute(outline, "xmlUrl")
        website_url = outline_attribute(outline, "htmlUrl")
        title = outline_attribute(outline, "title") || outline_attribute(outline, "text")

        if feed_url.blank?
          return malformed_entry(index, feed_url, title, website_url, "Missing feed URL")
        end

        unless valid_feed_url?(feed_url)
          return malformed_entry(index, feed_url, title, website_url, "Feed URL must be HTTP or HTTPS")
        end

        {
          id: "outline-#{index}",
          raw_outline_index: index,
          feed_url: feed_url,
          title: title,
          website_url: website_url,
          status: "valid",
          error: nil,
          health_status: nil,
          health_error: nil
        }
      end

      def malformed_entry(index, feed_url, title, website_url, error)
        {
          id: "outline-#{index}",
          raw_outline_index: index,
          feed_url: feed_url.presence,
          title: title,
          website_url: website_url,
          status: "malformed",
          error: error,
          health_status: nil,
          health_error: nil
        }
      end

      def outline_attribute(outline, name)
        attribute = outline.attribute_nodes.find { |attr| attr.name.casecmp(name).zero? }
        attribute&.value.to_s.presence
      end

      def valid_feed_url?(url)
        parsed = URI.parse(url)
        parsed.is_a?(URI::HTTP) && parsed.host.present?
      rescue URI::InvalidURIError
        false
      end

      def annotated_entries(selected_ids)
        selected_ids ||= []
        entries = Array(import_session.parsed_sources)
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

      def build_selection_from_params(selectable_entries)
        ids = import_session_params[:selected_source_ids]
        return [] unless ids

        Array(ids).map(&:to_s).uniq & selectable_entries.map { |entry| entry[:id] }
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

      def target_step
        permitted_step(import_session_params[:next_step]) || current_step || ImportSession.default_step
      end

      def permitted_step(value)
        step = value.to_s.presence
        return unless step

        ImportSession::STEP_ORDER.find { |candidate| candidate == step }
      end

      def import_session_params
        @import_session_params ||= begin
          raw = params[:import_session] || params["import_session"] || {}
          permitted = if raw.respond_to?(:permit)
            raw.permit(:next_step, :select_all, :select_none, selected_source_ids: [])
          else
            raw.to_h
          end

          SourceMonitor::Security::ParameterSanitizer.sanitize(permitted.to_h).with_indifferent_access
        end
      end
    end
  end
end
