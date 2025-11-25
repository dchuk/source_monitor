# frozen_string_literal: true

module SourceMonitor
  module Health
    class ImportSourceHealthCheck
      Result = Struct.new(:status, :error_message, :http_status, keyword_init: true)

      def initialize(feed_url:, client: nil)
        @feed_url = feed_url
        @client = client
      end

      def call
        return Result.new(status: "unhealthy", error_message: "Missing feed URL", http_status: nil) if feed_url.blank?

        response = connection.get(feed_url)
        status_code = response_status(response)
        healthy = healthy_status?(status_code)

        Result.new(
          status: healthy ? "healthy" : "unhealthy",
          error_message: healthy ? nil : error_for_status(status_code),
          http_status: status_code
        )
      rescue StandardError => error
        Result.new(status: "unhealthy", error_message: error.message, http_status: response_status(error))
      end

      private

      attr_reader :feed_url, :client

      def connection
        @connection ||= (client || SourceMonitor::HTTP.client(headers: {}, retry_requests: false))
      end

      def response_status(response)
        return response.status if response.respond_to?(:status)
        return response.response[:status] if response.respond_to?(:response) && response.response.is_a?(Hash)

        nil
      end

      def healthy_status?(status)
        status.present? && status.to_i.between?(200, 399)
      end

      def error_for_status(status)
        return "Request failed" if status.blank?

        "HTTP #{status}"
      end
    end
  end
end
