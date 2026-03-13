# frozen_string_literal: true

module SourceMonitor
  module Fetching
    class FetchError < StandardError
      CODE = "fetch_error"

      attr_reader :original_error, :response

      def initialize(message = nil, original_error: nil, response: nil)
        super(message || default_message)
        @original_error = original_error
        @response = response
      end

      def code
        self.class::CODE
      end

      def http_status
        response&.status
      end

      protected

      def default_message
        "Fetch error"
      end
    end

    class TimeoutError < FetchError
      CODE = "timeout"

      protected

      def default_message
        "Request timed out"
      end
    end

    class ConnectionError < FetchError
      CODE = "connection"

      protected

      def default_message
        "Connection failed"
      end
    end

    class HTTPError < FetchError
      CODE = "http_error"

      attr_reader :status

      def initialize(status:, message: nil, response: nil, original_error: nil)
        @status = status
        super(message || "HTTP #{status}", response: response, original_error: original_error)
      end

      protected

      def default_message
        "HTTP #{status}"
      end
    end

    class ParsingError < FetchError
      CODE = "parsing"

      protected

      def default_message
        "Unable to parse feed"
      end
    end

    class UnexpectedResponseError < FetchError
      CODE = "unexpected_response"

      protected

      def default_message
        "Unexpected response received"
      end
    end

    class BlockedError < FetchError
      CODE = "blocked"

      attr_reader :blocked_by

      def initialize(message = nil, blocked_by: "unknown", **kwargs)
        @blocked_by = blocked_by
        super(message, **kwargs)
      end

      protected

      def default_message
        "Feed blocked by #{blocked_by}"
      end
    end

    class AuthenticationError < FetchError
      CODE = "authentication"

      protected

      def default_message
        "Authentication required"
      end
    end
  end
end
