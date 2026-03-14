# frozen_string_literal: true

module SourceMonitor
  class BasePresenter < SimpleDelegator
    include ActionView::Helpers::NumberHelper
    include ActionView::Helpers::DateHelper
    include ActionView::Helpers::TextHelper

    def initialize(model)
      super(model)
    end

    def model
      __getobj__
    end

    alias_method :object, :model
  end
end
