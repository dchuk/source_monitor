# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class HTTPSettings
      attr_accessor :timeout,
        :open_timeout,
        :max_redirects,
        :user_agent,
        :proxy,
        :headers,
        :retry_max,
        :retry_interval,
        :retry_interval_randomness,
        :retry_backoff_factor,
        :retry_statuses,
        :ssl_ca_file,
        :ssl_ca_path,
        :ssl_verify

      def initialize
        reset!
      end

      def reset!
        @timeout = 15
        @open_timeout = 5
        @max_redirects = 5
        @user_agent = default_user_agent
        @proxy = nil
        @headers = {}
        @retry_max = 4
        @retry_interval = 0.5
        @retry_interval_randomness = 0.5
        @retry_backoff_factor = 2
        @retry_statuses = nil
        @ssl_ca_file = nil
        @ssl_ca_path = nil
        @ssl_verify = true
      end

      private

      def default_user_agent
        "Mozilla/5.0 (compatible; SourceMonitor/#{SourceMonitor::VERSION})"
      end
    end
  end
end
