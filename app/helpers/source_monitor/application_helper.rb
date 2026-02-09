# frozen_string_literal: true

module SourceMonitor
  module ApplicationHelper
    def source_monitor_stylesheet_bundle_tag
      stylesheet_link_tag("source_monitor/application", "data-turbo-track": "reload")
    rescue StandardError => error
      log_source_monitor_asset_error(:stylesheet, error)
      nil
    end

    def source_monitor_javascript_bundle_tag
      javascript_include_tag("source_monitor/application", "data-turbo-track": "reload", type: "module")
    rescue StandardError => error
      log_source_monitor_asset_error(:javascript, error)
      nil
    end

    def heatmap_bucket_classes(count, max_count)
      return "bg-slate-100 text-slate-500" if max_count.to_i.zero? || count.to_i.zero?

      ratio = count.to_f / max_count

      case ratio
      when 0...0.25
        "bg-blue-100 text-blue-800"
      when 0.25...0.5
        "bg-blue-200 text-blue-900"
      when 0.5...0.75
        "bg-blue-400 text-white"
      else
        "bg-blue-600 text-white"
      end
    end

    def fetch_interval_bucket_path(bucket, search_params, selected: false)
      query = fetch_interval_bucket_query(bucket, search_params, selected: selected)
      route_helpers = SourceMonitor::Engine.routes.url_helpers

      query.empty? ? route_helpers.sources_path : route_helpers.sources_path(q: query)
    end

    def fetch_interval_bucket_query(bucket, search_params, selected: false)
      base = (search_params || {}).dup
      base = base.except("fetch_interval_minutes_gteq", "fetch_interval_minutes_lt", "fetch_interval_minutes_lteq")

      query = if selected
        base
      else
        updated = base.dup
        updated["fetch_interval_minutes_gteq"] = bucket.min.to_i.to_s if bucket.respond_to?(:min) && bucket.min

        if bucket.respond_to?(:max) && bucket.max
          updated["fetch_interval_minutes_lt"] = bucket.max.to_i.to_s
        else
          updated.delete("fetch_interval_minutes_lt")
          updated.delete("fetch_interval_minutes_lteq")
        end

        updated
      end

      if query.respond_to?(:compact_blank)
        query.compact_blank
      else
        query.reject { |_key, value| value.respond_to?(:blank?) ? value.blank? : value.nil? }
      end
    end

    def fetch_interval_filter_label(bucket, filter)
      return bucket.label if bucket&.respond_to?(:label)
      return unless filter

      min = filter[:min]
      max = filter[:max]

      if min && max
        "#{min}-#{max} min"
      elsif min
        "#{min}+ min"
      else
        "Any interval"
      end
    end

    def fetch_schedule_window_label(group)
      start_time = group.respond_to?(:window_start) ? group.window_start : nil
      end_time = group.respond_to?(:window_end) ? group.window_end : nil

      return unless start_time || end_time

      if start_time && end_time
        "#{format_schedule_time(start_time)} – #{format_schedule_time(end_time)}"
      elsif start_time
        "After #{format_schedule_time(start_time)}"
      else
        nil
      end
    end

    def format_schedule_time(time)
      return unless time

      l(time.in_time_zone, format: :short)
    end

    def human_fetch_interval(minutes)
      return "—" if minutes.blank?

      total_minutes = minutes.to_i
      hours, remaining = total_minutes.divmod(60)
      parts = []
      parts << "#{hours}h" if hours.positive?
      parts << "#{remaining}m" if remaining.positive? || parts.empty?
      parts.join(" ")
    end

    # Unified status badge helper for both fetch and scrape operations
    ITEM_SCRAPE_STATUS_LABELS = {
      "pending" => "Pending",
      "processing" => "Processing",
      "success" => "Scraped",
      "failed" => "Failed",
      "partial" => "Partial",
      "disabled" => "Disabled",
      "idle" => "Not scraped"
    }.freeze

    # Maps asynchronous workflow states to badge styling/labels shared across the
    # engine. Item scraping builds on these core states, reusing the same colors
    # so the UI stays consistent across sources, items, and job dashboards.
    def async_status_badge(status, show_spinner: true)
      status_str = status.to_s

      label, classes, spinner = case status_str
      when "queued"
        [ "Queued", "bg-amber-100 text-amber-700", show_spinner ]
      when "pending"
        [ "Pending", "bg-amber-100 text-amber-700", show_spinner ]
      when "fetching", "processing"
        [ "Processing", "bg-blue-100 text-blue-700", show_spinner ]
      when "success"
        [ "Completed", "bg-green-100 text-green-700", false ]
      when "failed"
        [ "Failed", "bg-rose-100 text-rose-700", false ]
      when "partial"
        [ "Partial", "bg-amber-100 text-amber-700", false ]
      when "disabled"
        [ "Disabled", "bg-slate-200 text-slate-600", false ]
      when "idle"
        [ "Idle", "bg-slate-100 text-slate-600", false ]
      else
        [ "Ready", "bg-slate-100 text-slate-600", false ]
      end

      { label: label, classes: classes, show_spinner: spinner }
    end

    # Returns a normalized badge payload for the source show/item pages. The
    # status derives from the item's recorded scrape_status, falls back to the
    # source configuration, and always lands inside the known status set:
    # pending, processing, success, failed, partial, disabled, or idle.
    def item_scrape_status_badge(item:, source: nil, show_spinner: true)
      status = derive_item_scrape_status(item:, source: source)
      base_badge = async_status_badge(status, show_spinner: show_spinner)
      label = ITEM_SCRAPE_STATUS_LABELS.fetch(status) { base_badge[:label] }
      spinner = base_badge[:show_spinner] && %w[pending processing].include?(status)

      {
        status: status,
        label: label,
        classes: base_badge[:classes],
        show_spinner: spinner
      }
    end

    # Legacy helper for backwards compatibility
    def fetch_status_badge_classes(status)
      async_status_badge(status)
    end

    # Helper to render the loading spinner SVG
    def loading_spinner_svg(css_class: "mr-1 h-4 w-4 animate-spin text-blue-500")
      tag.svg(
        class: css_class,
        xmlns: "http://www.w3.org/2000/svg",
        fill: "none",
        viewBox: "0 0 24 24",
        aria: { hidden: "true" }
      ) do
        concat tag.circle(class: "opacity-25", cx: "12", cy: "12", r: "10", stroke: "currentColor", stroke_width: "4")
        concat tag.path(class: "opacity-75", fill: "currentColor", d: "M4 12a8 8 0 0 1 8-8v4a4 4 0 0 0-4 4H4z")
      end
    end

    def source_health_badge(source, override: nil)
      return override if override.present?

      status = source&.health_status.presence || "healthy"

      mapping = {
        "healthy" => { label: "Healthy", classes: "bg-green-100 text-green-700", show_spinner: false },
        "warning" => { label: "Needs Attention", classes: "bg-amber-100 text-amber-700", show_spinner: false },
        "critical" => { label: "Failing", classes: "bg-rose-100 text-rose-700", show_spinner: false },
        "declining" => { label: "Declining", classes: "bg-orange-100 text-orange-700", show_spinner: false },
        "improving" => { label: "Improving", classes: "bg-sky-100 text-sky-700", show_spinner: false },
        "auto_paused" => { label: "Auto-Paused", classes: "bg-amber-100 text-amber-700", show_spinner: false },
        "unknown" => { label: "Unknown", classes: "bg-slate-100 text-slate-600", show_spinner: false }
      }

      mapping.fetch(status) { mapping.fetch("unknown") }.merge(status: status)
    end

    def source_health_actions(source)
      status = source&.health_status.presence || "healthy"
      helpers = SourceMonitor::Engine.routes.url_helpers

      case status
      when "critical", "declining"
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
      when "auto_paused"
        [
          {
            key: :reset,
            label: "Reset to Active Status",
            description: "Clears the pause window, failure counters, and schedules the next fetch using the configured interval.",
            path: helpers.source_health_reset_path(source),
            method: :post,
            data: { testid: "source-health-action-reset" }
          }
        ]
      else
        []
      end
    end

    def interactive_health_status?(source, override: nil)
      return false if override.present?

      %w[critical declining auto_paused].include?(source&.health_status.presence)
    end

    def table_sort_direction(search_object, attribute)
      return unless search_object.respond_to?(:sorts)

      sort = search_object.sorts.detect { |s| s && s.name == attribute.to_s }
      sort&.dir
    end

    def table_sort_arrow(search_object, attribute, default: nil)
      direction = table_sort_direction(search_object, attribute) || default&.to_s

      case direction
      when "asc"
        "▲"
      when "desc"
        "▼"
      else
        "↕"
      end
    end

    def table_sort_aria(search_object, attribute)
      direction = table_sort_direction(search_object, attribute)

      case direction
      when "asc"
        "ascending"
      when "desc"
        "descending"
      else
        "none"
      end
    end

    def table_sort_link(search_object, attribute, label, frame:, default_order:, secondary: [], html_options: {})
      sort_targets = [ attribute, *Array(secondary) ]
      options = {
        default_order: default_order,
        hide_indicator: true
      }.merge(html_options)

      options[:data] = (options[:data] || {}).merge(turbo_frame: frame)
      options[:data][:turbo_action] ||= "advance"

      sort_link(search_object, attribute, sort_targets, options) do
        tag.span(label, class: "inline-flex items-center gap-1")
      end
    end

    def formatted_setting_value(value)
      case value
      when TrueClass
        "Enabled"
      when FalseClass
        "Disabled"
      when Hash
        value.to_json
      when Array
        value.join(", ")
      when NilClass
        "—"
      else
        value
      end
    end

    private

    def derive_item_scrape_status(item:, source: nil)
      return "idle" unless item

      status = item.scrape_status.to_s.presence
      return status if status.present?

      source ||= item.source
      return "disabled" if source&.scraping_enabled? == false
      return "success" if item.scraped_at.present?

      "idle"
    end

    def log_source_monitor_asset_error(kind, error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.debug("[SourceMonitor] Skipping #{kind} bundle include: #{error.message}")
    end
  end
end
