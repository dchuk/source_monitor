# frozen_string_literal: true

class TestSupportController < ApplicationController
  helper SourceMonitor::ApplicationHelper
  layout "source_monitor/application"

  def dropdown_without_dependency
  end
end
