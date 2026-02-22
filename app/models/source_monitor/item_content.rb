# frozen_string_literal: true

module SourceMonitor
  class ItemContent < ApplicationRecord
    belongs_to :item, class_name: "SourceMonitor::Item", inverse_of: :item_content, touch: true

    validates :item, presence: true

    has_many_attached :images if defined?(ActiveStorage)

    before_save :compute_word_counts

    SourceMonitor::ModelExtensions.register(self, :item_content)

    def total_word_count
      [ scraped_word_count, feed_word_count ].compact.max || 0
    end

    private

    def compute_word_counts
      compute_scraped_word_count
      compute_feed_word_count
    end

    def compute_scraped_word_count
      return unless scraped_content_changed? || new_record?

      self.scraped_word_count = scraped_content.present? ? scraped_content.split.size : nil
    end

    def compute_feed_word_count
      content = item&.content
      if content.blank?
        self.feed_word_count = nil
      else
        stripped = ActionView::Base.full_sanitizer.sanitize(content)
        self.feed_word_count = stripped.present? ? stripped.split.size : nil
      end
    end
  end
end
