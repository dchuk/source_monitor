# frozen_string_literal: true

require "active_support/core_ext/object/blank"

module SourceMonitor
  module Scrapers
    module Fetchers
      class HttpFetcher
        Result = Struct.new(:status, :body, :headers, :http_status, :error, :message, keyword_init: true)

        def initialize(http: SourceMonitor::HTTP)
          @http = http
          @aia_attempted = false
        end

        def fetch(url:, settings: nil)
          response = connection(settings).get(url)

          if success_status?(response.status)
            Result.new(status: :success, body: response.body, headers: response.headers, http_status: response.status)
          else
            Result.new(
              status: :failed,
              http_status: response.status,
              error: "http_error",
              message: "Non-success HTTP status"
            )
          end
        rescue Faraday::SSLError => error
          result = attempt_aia_recovery(url, settings)
          return result if result

          Result.new(status: :failed, error: error.class.name, message: error.message)
        rescue Faraday::ClientError => error
          Result.new(
            status: :failed,
            http_status: extract_status(error),
            error: error.class.name,
            message: error.message
          )
        rescue Faraday::Error => error
          Result.new(status: :failed, error: error.class.name, message: error.message)
        end

        private

        attr_reader :http

        def attempt_aia_recovery(url, settings)
          return if @aia_attempted

          @aia_attempted = true
          hostname = URI.parse(url).host
          intermediate = SourceMonitor::HTTP::AIAResolver.resolve(hostname)
          return unless intermediate

          store = SourceMonitor::HTTP::AIAResolver.enhanced_cert_store([ intermediate ])
          response = connection(settings, cert_store: store).get(url)

          if success_status?(response.status)
            Result.new(status: :success, body: response.body, headers: response.headers, http_status: response.status)
          else
            Result.new(status: :failed, http_status: response.status, error: "http_error", message: "Non-success HTTP status")
          end
        rescue StandardError
          nil
        end

        def connection(settings, cert_store: nil)
          normalized = normalize_settings(settings)
          http.client(
            proxy: normalized[:proxy],
            headers: normalized[:headers],
            timeout: normalized[:timeout] || SourceMonitor::HTTP::DEFAULT_TIMEOUT,
            open_timeout: normalized[:open_timeout] || SourceMonitor::HTTP::DEFAULT_OPEN_TIMEOUT,
            cert_store: cert_store
          )
        end

        def normalize_settings(settings)
          return {} unless settings

          settings = settings.respond_to?(:to_h) ? settings.to_h : settings
          {
            headers: (settings[:headers] || {}).to_h,
            timeout: settings[:timeout],
            open_timeout: settings[:open_timeout],
            proxy: settings[:proxy].presence
          }
        end

        def success_status?(status)
          status.to_i >= 200 && status.to_i < 300
        end

        def extract_status(error)
          candidates = []

          if error.respond_to?(:response_status)
            candidates << error.response_status
          end

          if error.respond_to?(:response)
            response = error.response
            if response.respond_to?(:[]) && response[:status]
              candidates << response[:status]
            elsif response.is_a?(Hash)
              candidates << response["status"]
              candidates << response[:status]
            end
          end

          if error.respond_to?(:message) && error.message
            error.message.scan(/\d{3}/).each do |number|
              candidates << number.to_i
            end
          end

          candidates.compact.first
        end
      end
    end
  end
end
