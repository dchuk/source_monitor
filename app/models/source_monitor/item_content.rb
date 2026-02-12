# frozen_string_literal: true

module SourceMonitor
  class ItemContent < ApplicationRecord
    belongs_to :item, class_name: "SourceMonitor::Item", inverse_of: :item_content, touch: true

    validates :item, presence: true

    has_many_attached :images

    SourceMonitor::ModelExtensions.register(self, :item_content)
  end
end
