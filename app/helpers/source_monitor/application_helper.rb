# frozen_string_literal: true

module SourceMonitor
  module ApplicationHelper
    include TableSortHelper
    include HealthBadgeHelper
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

    # Renders a clickable link that opens in a new tab with an external-link icon.
    # Returns the label as plain text if the URL is blank.
    def external_link_to(label, url, **options)
      return label if url.blank?

      css = options.delete(:class) || "text-blue-600 hover:text-blue-500"
      link_to(url, target: "_blank", rel: "noopener noreferrer", class: css, title: url, **options) do
        safe_join([ label, " ", external_link_icon ])
      end
    end

    # Extracts the domain from a URL, returning nil if parsing fails.
    def domain_from_url(url)
      return nil if url.blank?

      URI.parse(url.to_s).host
    rescue URI::InvalidURIError
      nil
    end

    # Renders the source favicon as an <img> tag or a colored-circle initials
    # placeholder when no favicon is attached.  Handles the case where
    # ActiveStorage is not loaded (host app without AS).
    #
    # Options:
    #   size: pixel dimension for width/height (default: 24)
    #   class: additional CSS classes
    def source_favicon_tag(source, size: 24, **options)
      css = options.delete(:class) || ""

      if favicon_attached?(source)
        favicon_image_tag(source, size: size, css: css)
      else
        favicon_placeholder_tag(source, size: size, css: css)
      end
    end

    private

    def external_link_icon
      tag.svg(
        class: "inline-block h-3 w-3 text-slate-400",
        xmlns: "http://www.w3.org/2000/svg",
        fill: "none",
        viewBox: "0 0 24 24",
        stroke_width: "2",
        stroke: "currentColor",
        aria: { hidden: "true" }
      ) do
        tag.path(
          stroke_linecap: "round",
          stroke_linejoin: "round",
          d: "M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25"
        )
      end
    end

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

    def favicon_attached?(source)
      defined?(ActiveStorage) &&
        source.respond_to?(:favicon) &&
        source.favicon.attached?
    end

    def favicon_image_tag(source, size:, css:)
      url = url_for(source.favicon)

      image_tag(url,
        alt: "#{source.name} favicon",
        width: size,
        height: size,
        class: "rounded object-contain #{css}".strip,
        style: "max-width: #{size}px; max-height: #{size}px;",
        loading: "lazy")
    rescue StandardError
      favicon_placeholder_tag(source, size: size, css: css)
    end

    def favicon_placeholder_tag(source, size:, css:)
      initial = source.name.to_s.strip.first.presence&.upcase || "?"
      hue = source.name.to_s.bytes.sum % 360
      bg_color = "hsl(#{hue}, 45%, 65%)"

      content_tag(:span,
        initial,
        class: "inline-flex items-center justify-center rounded-full text-white font-semibold #{css}".strip,
        style: "width: #{size}px; height: #{size}px; background-color: #{bg_color}; font-size: #{(size * 0.5).round}px; line-height: #{size}px;",
        title: source.name,
        "aria-hidden": "true")
    end
  end
end
