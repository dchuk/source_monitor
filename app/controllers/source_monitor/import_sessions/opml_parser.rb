# frozen_string_literal: true

module SourceMonitor
  module ImportSessions
    module OpmlParser
      extend ActiveSupport::Concern

      ALLOWED_CONTENT_TYPES = %w[text/xml application/xml text/x-opml application/opml].freeze
      GENERIC_CONTENT_TYPES = %w[application/octet-stream binary/octet-stream].freeze

      class UploadError < StandardError; end

      private

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

      def validate_upload!
        return [ "Upload an OPML file to continue." ] unless uploading_file?

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
    end
  end
end
