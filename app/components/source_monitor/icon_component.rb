# frozen_string_literal: true

module SourceMonitor
  class IconComponent < ApplicationComponent
    # SVG path data for each registered icon. Each entry is an array of hashes
    # with :d (path data) and optional per-path attributes like :fill, :stroke, etc.
    ICONS = {
      menu_dots: {
        view_box: "0 0 20 20",
        fill: "none",
        stroke: "currentColor",
        stroke_width: "1.5",
        paths: [
          { d: "M10.343 3.94a.75.75 0 0 0-1.093-.332l-.822.548a2.25 2.25 0 0 1-2.287.014l-.856-.506a.75.75 0 0 0-1.087.63l.03.988a2.25 2.25 0 0 1-.639 1.668l-.715.715a.75.75 0 0 0 0 1.06l.715.715a2.25 2.25 0 0 1 .639 1.668l-.03.988a.75.75 0 0 0 1.087.63l.856-.506a2.25 2.25 0 0 1 2.287.014l.822.548a.75.75 0 0 0 1.093-.332l.38-.926a2.25 2.25 0 0 1 1.451-1.297l.964-.258a.75.75 0 0 0 .534-.72v-.946a.75.75 0 0 0-.534-.72l-.964-.258a2.25 2.25 0 0 1-1.45-1.297l-.381-.926Z",
            stroke_linecap: "round", stroke_linejoin: "round" },
          { d: "M12 10a2 2 0 1 1-4 0 2 2 0 0 1 4 0Z",
            stroke_linecap: "round", stroke_linejoin: "round" }
        ]
      },
      refresh: {
        view_box: "0 0 24 24",
        fill: "none",
        stroke: "currentColor",
        stroke_width: "1.5",
        paths: [
          { d: "M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99",
            stroke_linecap: "round", stroke_linejoin: "round" }
        ]
      },
      chevron_down: {
        view_box: "0 0 20 20",
        fill: "currentColor",
        paths: [
          { d: "M5.23 7.21a.75.75 0 0 1 1.06.02L10 11.168l3.71-3.938a.75.75 0 1 1 1.08 1.04l-4.25 4.5a.75.75 0 0 1-1.08 0l-4.25-4.5a.75.75 0 0 1 .02-1.06z",
            fill_rule: "evenodd", clip_rule: "evenodd" }
        ]
      },
      external_link: {
        view_box: "0 0 24 24",
        fill: "none",
        stroke: "currentColor",
        stroke_width: "2",
        paths: [
          { d: "M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25",
            stroke_linecap: "round", stroke_linejoin: "round" }
        ]
      },
      spinner: {
        view_box: "0 0 24 24",
        fill: "none",
        spinner: true,
        elements: [
          { type: :circle, class: "opacity-25", cx: "12", cy: "12", r: "10",
            stroke: "currentColor", stroke_width: "4" },
          { type: :path, class: "opacity-75", fill: "currentColor",
            d: "M4 12a8 8 0 0 1 8-8v4a4 4 0 0 0-4 4H4z" }
        ]
      }
    }.freeze

    SIZE_CLASSES = {
      sm: "h-4 w-4",
      md: "h-5 w-5",
      lg: "h-6 w-6"
    }.freeze

    def initialize(name, size: :md, css_class: nil)
      @name = name.to_sym
      @size = size.to_sym
      @css_class = css_class
    end

    def call
      icon = ICONS[@name]
      return "".html_safe unless icon

      size_cls = SIZE_CLASSES.fetch(@size, SIZE_CLASSES[:md])
      classes = [size_cls, @css_class].compact.join(" ")

      if icon[:spinner]
        render_spinner(icon, classes)
      else
        render_standard(icon, classes)
      end
    end

    private

    def render_standard(icon, classes)
      svg_attrs = {
        class: classes,
        xmlns: "http://www.w3.org/2000/svg",
        viewBox: icon[:view_box],
        fill: icon[:fill] || "none",
        aria: { hidden: "true" }
      }
      svg_attrs[:stroke] = icon[:stroke] if icon[:stroke]
      svg_attrs[:stroke_width] = icon[:stroke_width] if icon[:stroke_width]

      tag.svg(**svg_attrs) do
        safe_join(icon[:paths].map { |path_data| render_path(path_data) })
      end
    end

    def render_path(path_data)
      attrs = { d: path_data[:d] }
      attrs[:stroke_linecap] = path_data[:stroke_linecap] if path_data[:stroke_linecap]
      attrs[:stroke_linejoin] = path_data[:stroke_linejoin] if path_data[:stroke_linejoin]
      attrs[:fill_rule] = path_data[:fill_rule] if path_data[:fill_rule]
      attrs[:clip_rule] = path_data[:clip_rule] if path_data[:clip_rule]
      attrs[:fill] = path_data[:fill] if path_data[:fill]
      tag.path(**attrs)
    end

    def render_spinner(icon, classes)
      tag.svg(
        class: classes,
        xmlns: "http://www.w3.org/2000/svg",
        fill: "none",
        viewBox: icon[:view_box],
        aria: { hidden: "true" }
      ) do
        safe_join(icon[:elements].map { |el| render_element(el) })
      end
    end

    def render_element(el)
      case el[:type]
      when :circle
        tag.circle(
          class: el[:class],
          cx: el[:cx], cy: el[:cy], r: el[:r],
          stroke: el[:stroke], stroke_width: el[:stroke_width]
        )
      when :path
        tag.path(class: el[:class], fill: el[:fill], d: el[:d])
      end
    end
  end
end
