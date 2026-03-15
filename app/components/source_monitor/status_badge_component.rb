# frozen_string_literal: true

module SourceMonitor
  # Renders a consistent status badge with color-coded styling and optional spinner.
  # Replaces 12+ duplicated badge markup patterns across views.
  #
  # Usage:
  #   render StatusBadgeComponent.new(status: "working")
  #   render StatusBadgeComponent.new(status: :fetching, size: :sm)
  #   render StatusBadgeComponent.new(status: "success", label: "Completed")
  class StatusBadgeComponent < ApplicationComponent
    STATUS_STYLES = {
      # Health statuses
      "working" => { classes: "bg-green-100 text-green-700", label: "Working" },
      "active" => { classes: "bg-green-100 text-green-700", label: "Active" },
      "improving" => { classes: "bg-sky-100 text-sky-700", label: "Improving" },
      # Success statuses
      "success" => { classes: "bg-green-100 text-green-700", label: "Success" },
      "completed" => { classes: "bg-green-100 text-green-700", label: "Completed" },
      # Failure statuses
      "failing" => { classes: "bg-rose-100 text-rose-700", label: "Failing" },
      "failed" => { classes: "bg-rose-100 text-rose-700", label: "Failed" },
      "error" => { classes: "bg-rose-100 text-rose-700", label: "Error" },
      # Warning statuses
      "declining" => { classes: "bg-yellow-100 text-yellow-700", label: "Declining" },
      "warning" => { classes: "bg-amber-100 text-amber-700", label: "Warning" },
      "partial" => { classes: "bg-amber-100 text-amber-700", label: "Partial" },
      # Pending/queued statuses
      "queued" => { classes: "bg-amber-100 text-amber-700", label: "Queued" },
      "pending" => { classes: "bg-amber-100 text-amber-700", label: "Pending" },
      # Processing statuses (show spinner)
      "fetching" => { classes: "bg-blue-100 text-blue-700", label: "Processing", spinner: true },
      "processing" => { classes: "bg-blue-100 text-blue-700", label: "Processing", spinner: true },
      # Inactive statuses
      "idle" => { classes: "bg-slate-100 text-slate-600", label: "Idle" },
      "disabled" => { classes: "bg-slate-200 text-slate-600", label: "Disabled" },
      "paused" => { classes: "bg-amber-100 text-amber-700", label: "Paused" },
      "blocked" => { classes: "bg-rose-100 text-rose-700", label: "Blocked" }
    }.freeze

    SPINNER_STATUSES = %w[fetching processing].freeze

    SIZE_CLASSES = {
      sm: "px-2 py-0.5 text-[10px]",
      md: "px-3 py-1 text-xs",
      lg: "px-4 py-1.5 text-sm"
    }.freeze

    DEFAULT_CLASSES = "bg-slate-100 text-slate-600"

    # @param status [String, Symbol] the status to display
    # @param label [String, nil] override the default label for the status
    # @param size [Symbol] :sm, :md, or :lg (default: :md)
    # @param show_spinner [Boolean] whether to show spinner for processing statuses (default: true)
    # @param data [Hash] additional data attributes for the badge element
    def initialize(status:, label: nil, size: :md, show_spinner: true, data: {})
      @status = status.to_s
      @label = label
      @size = size.to_sym
      @show_spinner = show_spinner
      @data = data
    end

    private

    def style_config
      STATUS_STYLES.fetch(@status) { { classes: DEFAULT_CLASSES, label: @status.humanize } }
    end

    def badge_classes
      color_classes = style_config[:classes]
      size_classes = SIZE_CLASSES.fetch(@size, SIZE_CLASSES[:md])
      "inline-flex items-center rounded-full font-semibold #{size_classes} #{color_classes}"
    end

    def display_label
      @label || style_config[:label]
    end

    def show_spinner?
      @show_spinner && (style_config[:spinner] || SPINNER_STATUSES.include?(@status))
    end

    def spinner_size_class
      case @size
      when :sm then "h-3 w-3"
      when :lg then "h-4.5 w-4.5"
      else "h-3.5 w-3.5"
      end
    end

    def data_attributes
      { testid: "status-badge", status: @status }.merge(@data)
    end
  end
end
