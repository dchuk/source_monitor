# frozen_string_literal: true

module SourceMonitor
  module Fetching
    class CloudflareBypass
      USER_AGENTS = [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"
      ].freeze

      CLOUDFLARE_MARKERS = FeedFetcher::CLOUDFLARE_MARKERS
      SNIFF_LIMIT = FeedFetcher::SNIFF_LIMIT
      DEFAULT_MAX_ATTEMPTS = 2
      BYPASS_TIMEOUT = 10

      attr_reader :response, :feed_url, :max_attempts

      def initialize(response:, feed_url:, max_attempts: DEFAULT_MAX_ATTEMPTS)
        @response = response
        @feed_url = feed_url
        @max_attempts = max_attempts
      end

      def call
        attempt_cookie_replay || attempt_ua_rotation
      end

      private

      def attempt_cookie_replay
        cookies = extract_cookies(response)
        return if cookies.blank?

        headers = { "Cookie" => cookies, "Cache-Control" => "no-cache", "Pragma" => "no-cache" }
        result = fetch_with_headers(headers)
        result unless cloudflare_blocked?(result)
      end

      def attempt_ua_rotation
        USER_AGENTS.first(max_attempts).each do |ua|
          headers = {
            "User-Agent" => ua,
            "Cache-Control" => "no-cache",
            "Pragma" => "no-cache"
          }
          result = fetch_with_headers(headers)
          return result unless cloudflare_blocked?(result)
        end

        nil
      end

      def fetch_with_headers(headers)
        client = SourceMonitor::HTTP.client(
          headers: headers,
          timeout: BYPASS_TIMEOUT,
          open_timeout: [ BYPASS_TIMEOUT / 2, 5 ].min,
          retry_requests: false
        )
        client.get(feed_url)
      rescue StandardError => e
        Rails.logger.warn("[SourceMonitor] CloudflareBypass request failed for #{feed_url}: #{e.class}: #{e.message}") if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        nil
      end

      def cloudflare_blocked?(response)
        return true if response.nil?

        body = response.body
        return true if body.blank?

        snippet = body[0, SNIFF_LIMIT].downcase
        CLOUDFLARE_MARKERS.any? { |marker| snippet.include?(marker.downcase) }
      end

      def extract_cookies(resp)
        set_cookie = resp&.headers&.dig("set-cookie")
        return if set_cookie.blank?

        Array(set_cookie).filter_map { |cookie|
          cookie.to_s.split(";").first.presence
        }.join("; ").presence
      end
    end
  end
end
