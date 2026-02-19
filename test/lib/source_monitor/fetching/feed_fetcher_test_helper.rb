# frozen_string_literal: true

module SourceMonitor
  module Fetching
    module FeedFetcherTestHelper
      private

      def build_source(name:, feed_url:, fetch_interval_minutes: 360, adaptive_fetching_enabled: true)
        create_source!(
          name: name,
          feed_url: feed_url,
          fetch_interval_minutes: fetch_interval_minutes,
          adaptive_fetching_enabled: adaptive_fetching_enabled
        )
      end

      def body_digest(body)
        Digest::SHA256.hexdigest(body)
      end
    end
  end
end
