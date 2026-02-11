# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]
    include ActionCable::TestHelper
    include Turbo::Broadcastable::TestHelper
  end
end
