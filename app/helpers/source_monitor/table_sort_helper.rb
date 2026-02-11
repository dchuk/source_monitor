# frozen_string_literal: true

module SourceMonitor
  module TableSortHelper
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
  end
end
