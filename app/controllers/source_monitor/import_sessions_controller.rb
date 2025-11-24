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
      persist_step!
      render :show
    end

    def update
      return handle_upload_step if @current_step == "upload"

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
      source_monitor_current_user&.id
    end

    def ensure_current_user!
      head :forbidden unless current_user_id
    end

    def authorize_import_session!
      head :forbidden unless @import_session.user_id == current_user_id
    end

    class UploadError < StandardError; end
  end
end
