# frozen_string_literal: true

module SourceMonitor
  class HealthController < ApplicationController
    def show
      render json: {
        status: "ok",
        metrics: SourceMonitor::Metrics.snapshot
      }
    end
  end
end
