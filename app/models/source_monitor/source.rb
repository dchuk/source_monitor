# frozen_string_literal: true

require "source_monitor/models/sanitizable"
require "source_monitor/models/url_normalizable"

module SourceMonitor
  class Source < ApplicationRecord
    include SourceMonitor::Models::Sanitizable
    include SourceMonitor::Models::UrlNormalizable

    has_one_attached :favicon if defined?(ActiveStorage)

    FETCH_STATUS_VALUES = %w[idle queued fetching failed].freeze

    has_many :all_items, class_name: "SourceMonitor::Item", inverse_of: :source, dependent: :destroy
    has_many :items, -> { active }, class_name: "SourceMonitor::Item", inverse_of: :source
    has_many :fetch_logs, class_name: "SourceMonitor::FetchLog", inverse_of: :source, dependent: :destroy
    has_many :scrape_logs, class_name: "SourceMonitor::ScrapeLog", inverse_of: :source, dependent: :destroy
    has_many :health_check_logs, class_name: "SourceMonitor::HealthCheckLog", inverse_of: :source, dependent: :destroy
    has_many :log_entries, class_name: "SourceMonitor::LogEntry", inverse_of: :source, dependent: :destroy

    # Scopes for common source states
    scope :active, -> { where(active: true) }
    scope :failed, lambda {
      failure = arel_table[:failure_count].gt(0)
      error_present = arel_table[:last_error].not_eq(nil)
      error_time_present = arel_table[:last_error_at].not_eq(nil)
      where(failure.or(error_present).or(error_time_present))
    }
    scope :healthy, -> { active.where(failure_count: 0, last_error: nil, last_error_at: nil) }

    # Use Rails attribute API for default values instead of after_initialize callbacks
    attribute :scrape_settings, default: -> { {} }
    attribute :custom_headers, default: -> { {} }
    attribute :metadata, default: -> { {} }
    attribute :fetch_status, :string, default: "idle"
    attribute :health_status, :string, default: "healthy"

    sanitizes_string_attributes :name, :feed_url, :website_url, :scraper_adapter
    sanitizes_hash_attributes :scrape_settings, :custom_headers, :metadata
    normalizes_urls :feed_url, :website_url
    validates_url_format :feed_url, :website_url

    validates :name, presence: true
    validates :feed_url, presence: true, uniqueness: { case_sensitive: false }
    validates :fetch_interval_minutes, numericality: { greater_than: 0 }
    validates :scraper_adapter, presence: true
    validates :items_retention_days, numericality: { allow_nil: true, only_integer: true, greater_than_or_equal_to: 0 }
    validates :max_items, numericality: { allow_nil: true, only_integer: true, greater_than_or_equal_to: 0 }
    validates :fetch_status, inclusion: { in: FETCH_STATUS_VALUES }
    validates :fetch_retry_attempt, numericality: { greater_than_or_equal_to: 0, only_integer: true }

    validate :health_auto_pause_threshold_within_bounds

    SourceMonitor::ModelExtensions.register(self, :source)

    class << self
      # Convert scope to class method to make reference_time parameter explicit
      # Scopes with internal variables should be class methods per Rails best practices
      def due_for_fetch(reference_time: Time.current)
        active.where(arel_table[:next_fetch_at].eq(nil).or(arel_table[:next_fetch_at].lteq(reference_time)))
      end

      def ransackable_attributes(_auth_object = nil)
        %w[name feed_url website_url created_at fetch_interval_minutes items_count last_fetched_at]
      end

      def ransackable_associations(_auth_object = nil)
        []
      end
    end

    def fetch_interval_minutes=(value)
      self[:fetch_interval_minutes] = value.presence && value.to_i
    end

    def fetch_interval_hours=(value)
      self.fetch_interval_minutes = (value.to_f * 60).round if value.present?
    end

    def fetch_interval_hours
      return 0 unless fetch_interval_minutes

      fetch_interval_minutes.to_f / 60.0
    end

    def fetch_circuit_open?
      fetch_circuit_until.present? && fetch_circuit_until.future?
    end

    def fetch_retry_attempt
      value = super
      value.present? ? value : 0
    end

    def auto_paused?
      auto_paused_until.present? && auto_paused_until.future?
    end

    def reset_items_counter!
      # Recalculate items_count from actual active (non-deleted) items
      actual_count = items.count
      update_columns(items_count: actual_count)
    end

    private

    def health_auto_pause_threshold_within_bounds
      return if health_auto_pause_threshold.nil?

      value = health_auto_pause_threshold.to_f
      return if value >= 0 && value <= 1

      errors.add(:health_auto_pause_threshold, "must be between 0 and 1")
    end
  end
end
