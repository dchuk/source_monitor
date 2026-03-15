# frozen_string_literal: true

require "view_component"

module SourceMonitor
  class ApplicationComponent < ViewComponent::Base
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::FormTagHelper
  end
end
