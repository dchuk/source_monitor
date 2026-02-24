# frozen_string_literal: true

module SourceMonitor
  module Fetching
    class FeedFetcher
      class AdaptiveInterval
        MIN_FETCH_INTERVAL = 5.minutes.to_f
        MAX_FETCH_INTERVAL = 24.hours.to_f
        INCREASE_FACTOR = 1.25
        DECREASE_FACTOR = 0.75
        FAILURE_INCREASE_FACTOR = 1.5
        JITTER_PERCENT = 0.1

        attr_reader :source, :jitter_proc

        def initialize(source:, jitter_proc: nil)
          @source = source
          @jitter_proc = jitter_proc
        end

        def apply_adaptive_interval!(attributes, content_changed:, failure: false)
          if source.adaptive_fetching_enabled?
            interval_seconds = compute_next_interval_seconds(content_changed:, failure:)
            scheduled_time = Time.current + adjusted_interval_with_jitter(interval_seconds)
            scheduled_time = [ scheduled_time, source.backoff_until ].compact.max if source.backoff_until.present?

            attributes[:fetch_interval_minutes] = interval_minutes_for(interval_seconds)
            attributes[:next_fetch_at] = scheduled_time
            attributes[:backoff_until] = failure ? scheduled_time : nil
          else
            fixed_minutes = [ source.fetch_interval_minutes.to_i, 1 ].max
            fixed_seconds = fixed_minutes * 60.0
            attributes[:next_fetch_at] = Time.current + adjusted_interval_with_jitter(fixed_seconds)
            attributes[:backoff_until] = nil
          end
        end

        def compute_next_interval_seconds(content_changed:, failure:)
          current = [ current_interval_seconds, min_fetch_interval_seconds ].max

          next_interval = if failure
                            current * failure_increase_factor_value
          elsif content_changed
                            current * decrease_factor_value
          else
                            current * increase_factor_value
          end

          next_interval = min_fetch_interval_seconds if next_interval < min_fetch_interval_seconds
          next_interval = max_fetch_interval_seconds if next_interval > max_fetch_interval_seconds
          next_interval.to_f
        end

        def adjusted_interval_with_jitter(interval_seconds)
          jitter = jitter_offset(interval_seconds)
          adjusted = interval_seconds + jitter
          adjusted = min_fetch_interval_seconds if adjusted < min_fetch_interval_seconds
          adjusted
        end

        def jitter_offset(interval_seconds)
          return 0 if interval_seconds <= 0
          return jitter_proc.call(interval_seconds) if jitter_proc.respond_to?(:call)

          jitter_range = interval_seconds * jitter_percent_value
          return 0 if jitter_range <= 0

          ((rand * 2) - 1) * jitter_range
        end

        def interval_minutes_for(interval_seconds)
          minutes = (interval_seconds / 60.0).round
          [ minutes, 1 ].max
        end

        def configured_seconds(minutes_value, default)
          minutes = extract_numeric(minutes_value)
          return default unless minutes && minutes.positive?

          minutes * 60.0
        end

        def configured_positive(value, default)
          number = extract_numeric(value)
          return default unless number && number.positive?

          number
        end

        def configured_non_negative(value, default)
          number = extract_numeric(value)
          return default if number.nil?

          number.negative? ? 0.0 : number
        end

        def extract_numeric(value)
          return value if value.is_a?(Numeric)
          return value.to_f if value.respond_to?(:to_f)

          nil
        rescue StandardError
          nil
        end

        private

        def current_interval_seconds
          source.fetch_interval_minutes.to_f * 60.0
        end

        def min_fetch_interval_seconds
          configured_seconds(fetching_config&.min_interval_minutes, MIN_FETCH_INTERVAL)
        end

        def max_fetch_interval_seconds
          configured_seconds(fetching_config&.max_interval_minutes, MAX_FETCH_INTERVAL)
        end

        def increase_factor_value
          configured_positive(fetching_config&.increase_factor, INCREASE_FACTOR)
        end

        def decrease_factor_value
          configured_positive(fetching_config&.decrease_factor, DECREASE_FACTOR)
        end

        def failure_increase_factor_value
          configured_positive(fetching_config&.failure_increase_factor, FAILURE_INCREASE_FACTOR)
        end

        def jitter_percent_value
          configured_non_negative(fetching_config&.jitter_percent, JITTER_PERCENT)
        end

        def fetching_config
          SourceMonitor.config.fetching
        end
      end
    end
  end
end
