# frozen_string_literal: true

module SourceMonitor
  module HealthBadgeHelper
    def source_health_badge(source, override: nil)
      return override if override.present?

      status = source&.health_status.presence || "working"

      mapping = {
        "working" => { label: "Working", classes: "bg-green-100 text-green-700", show_spinner: false },
        "declining" => { label: "Declining", classes: "bg-yellow-100 text-yellow-700", show_spinner: false },
        "improving" => { label: "Improving", classes: "bg-sky-100 text-sky-700", show_spinner: false },
        "failing" => { label: "Failing", classes: "bg-rose-100 text-rose-700", show_spinner: false },
        "unknown" => { label: "Unknown", classes: "bg-slate-100 text-slate-600", show_spinner: false }
      }

      mapping.fetch(status) { mapping.fetch("unknown") }.merge(status: status)
    end

    def source_health_actions(source)
      status = source&.health_status.presence || "working"
      helpers = SourceMonitor::Engine.routes.url_helpers

      case status
      when "failing", "declining"
        [
          {
            key: :full_fetch,
            label: "Queue Full Fetch",
            description: "Runs the full fetch pipeline immediately and updates items if the feed responds.",
            path: helpers.source_fetch_path(source),
            method: :post,
            data: { testid: "source-health-action-full_fetch" }
          },
          {
            key: :health_check,
            label: "Run Health Check",
            description: "Sends a single request to confirm the feed is reachable without modifying stored items.",
            path: helpers.source_health_check_path(source),
            method: :post,
            data: { testid: "source-health-action-health_check" }
          }
        ]
      else
        []
      end
    end

    def interactive_health_status?(source, override: nil)
      return false if override.present?

      %w[failing declining].include?(source&.health_status.presence)
    end
  end
end
