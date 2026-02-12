# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class ImagesSettings
      attr_accessor :download_to_active_storage,
        :max_download_size,
        :download_timeout,
        :allowed_content_types

      DEFAULT_MAX_DOWNLOAD_SIZE = 10 * 1024 * 1024 # 10 MB
      DEFAULT_DOWNLOAD_TIMEOUT = 30 # seconds
      DEFAULT_ALLOWED_CONTENT_TYPES = %w[
        image/jpeg
        image/png
        image/gif
        image/webp
        image/svg+xml
      ].freeze

      def initialize
        reset!
      end

      def reset!
        @download_to_active_storage = false
        @max_download_size = DEFAULT_MAX_DOWNLOAD_SIZE
        @download_timeout = DEFAULT_DOWNLOAD_TIMEOUT
        @allowed_content_types = DEFAULT_ALLOWED_CONTENT_TYPES.dup
      end

      def download_enabled?
        !!download_to_active_storage
      end
    end
  end
end
