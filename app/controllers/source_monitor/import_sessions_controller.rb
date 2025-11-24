# frozen_string_literal: true

require "nokogiri"
require "uri"

module SourceMonitor
  class ImportSessionsController < ApplicationController
    before_action :ensure_current_user!
    before_action :set_import_session, only: %i[show update destroy]
    before_action :authorize_import_session!, only: %i[show update destroy]
    before_action :set_wizard_step, only: %i[show update]

    ALLOWED_CONTENT_TYPES = %w[text/xml application/xml text/x-opml application/opml].freeze
    GENERIC_CONTENT_TYPES = %w[application/octet-stream binary/octet-stream].freeze

    def new
      import_session = ImportSession.create!(
        user_id: current_user_id,
        current_step: ImportSession.default_step
      )

      redirect_to source_monitor.step_import_session_path(import_session, step: import_session.current_step)
    end

    def create
      import_session = ImportSession.create!(
        user_id: current_user_id,
        current_step: ImportSession.default_step
      )

      redirect_to source_monitor.step_import_session_path(import_session, step: import_session.current_step)
    end

    def show
      prepare_preview_context if @current_step == "preview"
      persist_step!
      render :show
    end

    def update
      return handle_upload_step if @current_step == "upload"
      return handle_preview_step if @current_step == "preview"

      @import_session.update!(session_attributes)
      @current_step = target_step
      @import_session.update_column(:current_step, @current_step) if @import_session.current_step != @current_step

      respond_to do |format|
        format.turbo_stream { render :show }
        format.html { redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step) }
      end
    end

    def destroy
      @import_session.destroy
      redirect_to source_monitor.sources_path, notice: "Import canceled"
    end

    private

    def set_import_session
      @import_session = ImportSession.find(params[:id])
    end

    def set_wizard_step
      @wizard_steps = ImportSession::STEP_ORDER
      @current_step = permitted_step(params[:step]) || @import_session.current_step || ImportSession.default_step
    end

    def persist_step!
      return if @import_session.current_step == @current_step

      @import_session.update_column(:current_step, @current_step)
    end

    def session_attributes
      attrs = state_params.except(:next_step, :current_step, "next_step", "current_step")
      attrs[:opml_file_metadata] = build_file_metadata if uploading_file?
      attrs[:current_step] = target_step
      attrs
    end

    def handle_upload_step
      @upload_errors = validate_upload!

      if @upload_errors.any?
        render :show, status: :unprocessable_entity
        return
      end

      parsed_entries = parse_opml_file(params[:opml_file])
      valid_entries = parsed_entries.select { |entry| entry[:status] == "valid" }

      if valid_entries.empty?
        @upload_errors = ["We couldn't find any valid feeds in that OPML file. Check the file and try again."]
        @import_session.update!(opml_file_metadata: build_file_metadata, parsed_sources: parsed_entries, current_step: "upload")
        render :show, status: :unprocessable_entity
        return
      end

      @import_session.update!(
        opml_file_metadata: build_file_metadata.merge("uploaded_at" => Time.current),
        parsed_sources: parsed_entries,
        current_step: target_step
      )

      @current_step = target_step

      respond_to do |format|
        format.turbo_stream { render :show }
        format.html { redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step) }
      end
    rescue UploadError => error
      @upload_errors = [error.message]
      render :show, status: :unprocessable_entity
    end

    def handle_preview_step
      @selected_source_ids = extract_selected_ids

      valid_ids = selectable_entries.index_by { |entry| entry[:id] }.slice(*@selected_source_ids).keys
      @import_session.update!(selected_source_ids: valid_ids)

      if advancing_from_preview? && valid_ids.empty?
        @selection_error = "Select at least one new source to continue."
        prepare_preview_context
        render :show, status: :unprocessable_entity
        return
      end

      @current_step = target_step
      @import_session.update_column(:current_step, @current_step) if @import_session.current_step != @current_step
      prepare_preview_context

      respond_to do |format|
        format.turbo_stream { render :show }
        format.html { redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step) }
      end
    end

    def state_params
      @state_params ||= begin
        permitted = params.fetch(:import_session, {}).permit(
          :current_step,
          :next_step,
          parsed_sources: [],
          selected_source_ids: [],
          bulk_settings: {},
          opml_file_metadata: {}
        )

        SourceMonitor::Security::ParameterSanitizer.sanitize(permitted.to_h)
      end
    end

    def build_file_metadata
      return {} unless params[:opml_file].respond_to?(:original_filename)

      file = params[:opml_file]
      {
        "filename" => file.original_filename,
        "byte_size" => file.size,
        "content_type" => file.content_type
      }
    end

    def uploading_file?
      params[:opml_file].present?
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

    def validate_upload!
      return ["Upload an OPML file to continue."] unless uploading_file?

      file = params[:opml_file]
      errors = []

      errors << "The uploaded file is empty. Choose another OPML file." if file.size.to_i <= 0

      if file.content_type.present? && !content_type_allowed?(file.content_type) && !generic_content_type?(file.content_type)
        errors << "Upload must be an OPML or XML file."
      end

      errors
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

      outlines = document.xpath("//outline")

      entries = []

      outlines.each_with_index do |outline, index|
        next unless outline.attribute_nodes.any? { |attr| attr.name.casecmp("xmlurl").zero? }

        entries << build_entry(outline, index)
      end

      entries
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
        error: nil
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
        error: error
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

    def current_user_id
      return source_monitor_current_user&.id if source_monitor_current_user

      return fallback_user_id unless SourceMonitor::Security::Authentication.authentication_configured?

      nil
    end

    def ensure_current_user!
      head :forbidden unless current_user_id
    end

    def fallback_user_id
      return @fallback_user_id if defined?(@fallback_user_id)

      unless defined?(::User) && ::User.respond_to?(:first)
        @fallback_user_id = nil
        return @fallback_user_id
      end

      existing = ::User.first
      if existing
        @fallback_user_id = existing.id
        return @fallback_user_id
      end

      @fallback_user_id = create_guest_user&.id
    rescue StandardError
      @fallback_user_id = nil
    end

    def create_guest_user
      return unless defined?(::User)

      attributes = {}
      ::User.columns_hash.each do |name, column|
        next if name == ::User.primary_key

        if column.default.nil? && !column.null
          attributes[name] = guest_value_for(column)
        end
      end

      ::User.create(attributes)
    end

    def guest_value_for(column)
      case column.type
      when :string, :text
        "source_monitor_guest"
      when :boolean
        false
      when :integer
        0
      when :datetime, :timestamp
        Time.current
      else
        column.default
      end
    end

    def authorize_import_session!
      return if !SourceMonitor::Security::Authentication.authentication_configured?

      head :forbidden unless @import_session.user_id == current_user_id
    end

    def prepare_preview_context
      @filter = permitted_filter(params[:filter]) || "all"
      @page = normalize_page_param(params[:page])
      @selected_source_ids = Array(@import_session.selected_source_ids).map(&:to_s)

      @preview_entries = annotated_entries
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

    def annotated_entries
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
          selected: @selected_source_ids.include?(entry[:id])
        )
      end
    end

    def normalize_entry(entry)
      entry = entry.to_h
      {
        id: entry[:id]&.to_s || entry["id"]&.to_s || entry[:feed_url]&.to_s || entry["feed_url"]&.to_s,
        feed_url: entry[:feed_url].presence || entry["feed_url"].presence,
        title: entry[:title].presence || entry["title"].presence,
        website_url: entry[:website_url].presence || entry["website_url"].presence,
        status: entry[:status].presence || entry["status"].presence || "valid",
        error: entry[:error].presence || entry["error"].presence,
        raw_outline_index: entry[:raw_outline_index] || entry["raw_outline_index"]
      }
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

    def extract_selected_ids
      ids = params.dig(:import_session, :selected_source_ids)
      return [] unless ids

      Array(ids).map { |id| id.to_s }.uniq
    end

    def selectable_entries
      @selectable_entries ||= annotated_entries.select { |entry| entry[:selectable] }
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

    class UploadError < StandardError; end
  end
end
