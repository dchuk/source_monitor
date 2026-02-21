# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class FaviconsSettings
      attr_accessor :enabled,
        :fetch_timeout,
        :max_download_size,
        :retry_cooldown_days,
        :allowed_content_types

      DEFAULT_FETCH_TIMEOUT = 5 # seconds
      DEFAULT_MAX_DOWNLOAD_SIZE = 1 * 1024 * 1024 # 1 MB
      DEFAULT_RETRY_COOLDOWN_DAYS = 7
      DEFAULT_ALLOWED_CONTENT_TYPES = %w[
        image/x-icon
        image/vnd.microsoft.icon
        image/png
        image/jpeg
        image/gif
        image/svg+xml
        image/webp
      ].freeze

      def initialize
        reset!
      end

      def reset!
        @enabled = true
        @fetch_timeout = DEFAULT_FETCH_TIMEOUT
        @max_download_size = DEFAULT_MAX_DOWNLOAD_SIZE
        @retry_cooldown_days = DEFAULT_RETRY_COOLDOWN_DAYS
        @allowed_content_types = DEFAULT_ALLOWED_CONTENT_TYPES.dup
      end

      def enabled?
        !!enabled && !!defined?(ActiveStorage)
      end
    end
  end
end
