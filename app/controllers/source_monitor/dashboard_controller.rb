# frozen_string_literal: true

module SourceMonitor
  class DashboardController < ApplicationController
    def index
      queries = SourceMonitor::Dashboard::Queries.new
      url_helpers = SourceMonitor::Engine.routes.url_helpers

      @stats = queries.stats
      @recent_activity = SourceMonitor::Dashboard::RecentActivityPresenter.new(
        queries.recent_activity,
        url_helpers:
      ).to_a
      @quick_actions = SourceMonitor::Dashboard::QuickActionsPresenter.new(
        queries.quick_actions,
        url_helpers:
      ).to_a
      @job_adapter = SourceMonitor::Jobs::Visibility.adapter_name
      @job_metrics = queries.job_metrics
      @schedule_pages = schedule_pages_params
      fetch_schedule = queries.upcoming_fetch_schedule(pages: @schedule_pages)
      @fetch_schedule_groups = fetch_schedule.groups
      @fetch_schedule_reference_time = fetch_schedule.reference_time
      @scrape_candidates_count = @stats[:scrape_candidates_count]
      @scrape_recommendation_threshold = SourceMonitor.config.scraping.scrape_recommendation_threshold
      @mission_control_enabled = SourceMonitor.mission_control_enabled?
      @mission_control_dashboard_path = SourceMonitor.mission_control_dashboard_path
    end

    private

    def schedule_pages_params
      params.fetch(:schedule_pages, {}).permit!.to_h
    end
  end
end
