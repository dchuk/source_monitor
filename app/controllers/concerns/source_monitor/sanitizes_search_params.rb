# frozen_string_literal: true

module SourceMonitor
  module SanitizesSearchParams
    extend ActiveSupport::Concern

    included do
      class_attribute :_search_scope, instance_writer: false
      class_attribute :_default_search_sorts, instance_writer: false, default: [ "created_at desc" ]
    end

    class_methods do
      def searchable_with(scope:, default_sorts: [ "created_at desc" ])
        self._search_scope = scope
        self._default_search_sorts = default_sorts
      end
    end

    private

    def build_search_query(scope = nil, params: sanitized_search_params)
      base_scope = scope || search_scope
      query = base_scope.ransack(params)
      query.sorts = default_search_sorts if query.sorts.blank?
      query
    end

    def search_scope
      if _search_scope.respond_to?(:call)
        instance_exec(&_search_scope)
      else
        _search_scope
      end
    end

    def default_search_sorts
      _default_search_sorts
    end

    def sanitized_search_params
      raw = params[:q]
      return {} unless raw

      # Ransack requires a plain Hash, not ActionController::Parameters. Using
      # to_unsafe_h here is safe because the values are immediately passed through
      # ParameterSanitizer.sanitize which applies an explicit allowlist, then
      # stripped and blank-filtered below before reaching Ransack.
      hash =
        if raw.respond_to?(:to_unsafe_h)
          raw.to_unsafe_h
        elsif raw.respond_to?(:to_h)
          raw.to_h
        elsif raw.is_a?(Hash)
          raw
        else
          {}
        end

      sanitized = SourceMonitor::Security::ParameterSanitizer.sanitize(hash)

      sanitized_params = sanitized.each_with_object({}) do |(key, value), memo|
        next if value.nil?

        cleaned_value = value.is_a?(String) ? value.strip : value
        next if cleaned_value.respond_to?(:blank?) ? cleaned_value.blank? : cleaned_value.nil?

        memo[key.to_s] = cleaned_value
      end

      assign_sanitized_params(sanitized_params)

      sanitized_params
    end

    def assign_sanitized_params(sanitized_params)
      return unless respond_to?(:params) && params

      if params.is_a?(ActionController::Parameters)
        params[:q] = ActionController::Parameters.new(sanitized_params)
      else
        params[:q] = sanitized_params
      end
    end
  end
end
