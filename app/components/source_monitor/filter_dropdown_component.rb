# frozen_string_literal: true

module SourceMonitor
  # Renders a labeled filter dropdown with auto-submit behavior.
  # Used across sources, items, and logs index views to provide
  # consistent filter select styling and behavior.
  class FilterDropdownComponent < ApplicationComponent
    SELECT_CLASSES = "rounded-md border border-slate-200 bg-white px-2 py-2 text-sm " \
                     "text-slate-700 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
    LABEL_CLASSES = "block text-xs font-medium text-slate-500 mb-1"

    # @param label [String] visible label text for the dropdown
    # @param param_name [Symbol, String] the form parameter name
    # @param options [Array<Array>] array of [label, value] pairs for the select
    # @param selected_value [String, nil] currently selected value
    # @param form [ActionView::Helpers::FormBuilder, nil] optional form builder for Ransack integration
    def initialize(label:, param_name:, options:, selected_value: nil, form: nil)
      @label = label
      @param_name = param_name
      @options = options
      @selected_value = selected_value.to_s
      @form = form
    end

    def call
      content_tag(:div) do
        safe_join([ render_label, render_select ])
      end
    end

    private

    def render_label
      if @form
        @form.label(@param_name, @label, class: LABEL_CLASSES)
      else
        label_tag(@param_name, @label, class: LABEL_CLASSES)
      end
    end

    def render_select
      if @form
        @form.select(
          @param_name,
          options_for_select(@options, @selected_value),
          {},
          class: SELECT_CLASSES,
          onchange: "this.form.requestSubmit()"
        )
      else
        select_tag(
          @param_name,
          options_for_select(@options, @selected_value),
          class: SELECT_CLASSES,
          onchange: "this.form.requestSubmit()"
        )
      end
    end
  end
end
