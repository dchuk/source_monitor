# frozen_string_literal: true

module SourceMonitor
  class DeprecatedOptionError < StandardError; end

  class Configuration
    # Registry for deprecated configuration options.
    #
    # Engine developers register deprecations at boot time via the DSL:
    #
    #   SourceMonitor::Configuration::DeprecationRegistry.register(
    #     "http.old_proxy_url",
    #     removed_in: "0.5.0",
    #     replacement: "http.proxy",
    #     severity: :warning,
    #     message: "Use config.http.proxy instead"
    #   )
    #
    # When a host app's initializer accesses a deprecated option, the
    # trapping method fires automatically:
    #   - :warning  -- logs via Rails.logger.warn and forwards to replacement
    #   - :error    -- raises SourceMonitor::DeprecatedOptionError
    #
    class DeprecationRegistry
      # Maps settings accessor names (as used on Configuration) to their classes.
      SETTINGS_CLASSES = {
        "http" => "HTTPSettings",
        "fetching" => "FetchingSettings",
        "health" => "HealthSettings",
        "scraping" => "ScrapingSettings",
        "retention" => "RetentionSettings",
        "realtime" => "RealtimeSettings",
        "authentication" => "AuthenticationSettings",
        "images" => "ImagesSettings",
        "scrapers" => "ScraperRegistry",
        "events" => "Events",
        "models" => "Models"
      }.freeze

      class << self
        # Register a deprecated configuration option.
        #
        # @param path [String] dot-notation path, e.g. "http.old_proxy_url" or "old_queue_prefix"
        # @param removed_in [String] version in which the option was deprecated
        # @param replacement [String, nil] dot-notation path to the replacement option
        # @param severity [:warning, :error] :warning logs + forwards, :error raises
        # @param message [String, nil] additional migration guidance
        def register(path, removed_in:, replacement: nil, severity: :warning, message: nil)
          segments = path.split(".")
          source_prefix = nil
          if segments.length == 1
            target_class = Configuration
            option_name = segments.first
          else
            source_prefix = segments.first
            option_name = segments.last
            class_name = SETTINGS_CLASSES[source_prefix]
            raise ArgumentError, "Unknown settings accessor: #{source_prefix}" unless class_name

            target_class = Configuration.const_get(class_name)
          end

          deprecation_message = build_message(path, removed_in, replacement, message)

          if target_class.method_defined?(:"#{option_name}=") || target_class.method_defined?(option_name.to_sym)
            warn "[SourceMonitor] DeprecationRegistry: '#{path}' already exists on #{target_class.name}. " \
                 "Skipping trap definition -- the option is not yet removed/renamed."
            entries[path] = { path: path, removed_in: removed_in, replacement: replacement,
                              severity: severity, message: deprecation_message, skipped: true }
            return
          end

          define_trap_methods(target_class, option_name, deprecation_message, severity, replacement,
                              source_prefix: source_prefix)

          entries[path] = { path: path, removed_in: removed_in, replacement: replacement,
                            severity: severity, message: deprecation_message, skipped: false }
        end

        # Remove all registered deprecation traps and clear state.
        # Essential for test isolation.
        def clear!
          defined_methods.each do |target_class, method_name|
            target_class.remove_method(method_name) if target_class.method_defined?(method_name)
          rescue NameError
            # Method was already removed or never defined; ignore.
          end

          @entries = {}
          @defined_methods = []
        end

        # Returns a duplicate of the entries hash for inspection.
        def entries
          @entries ||= {}
        end

        # Check if a path is registered.
        def registered?(path)
          entries.key?(path)
        end

        # No-op hook for future "default changed" checks.
        # Called by Configuration#check_deprecations! after the configure block.
        def check_defaults!(_config)
          # Reserved for future use. Phases may add checks like:
          # "option X changed its default from A to B in version Y"
        end

        private

        def defined_methods
          @defined_methods ||= []
        end

        def build_message(path, removed_in, replacement, extra_message)
          parts = +"[SourceMonitor] DEPRECATION: '#{path}' was deprecated in v#{removed_in}"
          parts << " and replaced by '#{replacement}'" if replacement
          parts << ". #{extra_message}" if extra_message
          parts << "." unless parts.end_with?(".")
          parts.freeze
        end

        def define_trap_methods(target_class, option_name, deprecation_message, severity, replacement, source_prefix: nil)
          writer_name = :"#{option_name}="
          reader_name = option_name.to_sym

          case severity
          when :warning
            define_warning_writer(target_class, writer_name, deprecation_message, replacement, source_prefix)
            define_warning_reader(target_class, reader_name, deprecation_message, replacement, source_prefix)
          when :error
            define_error_method(target_class, writer_name, deprecation_message)
            define_error_method(target_class, reader_name, deprecation_message)
          else
            raise ArgumentError, "Unknown severity: #{severity}. Must be :warning or :error."
          end

          defined_methods.push([ target_class, writer_name ], [ target_class, reader_name ])
        end

        def define_warning_writer(target_class, writer_name, deprecation_message, replacement, source_prefix)
          replacement_writer = replacement_setter_for(replacement, source_prefix)

          target_class.define_method(writer_name) do |value|
            Rails.logger.warn(deprecation_message)
            if replacement_writer
              resolve_replacement_target(replacement_writer[:target]).public_send(
                replacement_writer[:setter], value
              )
            end
          end
        end

        def define_warning_reader(target_class, reader_name, deprecation_message, replacement, source_prefix)
          replacement_reader = replacement_getter_for(replacement, source_prefix)

          target_class.define_method(reader_name) do
            Rails.logger.warn(deprecation_message)
            if replacement_reader
              resolve_replacement_target(replacement_reader[:target]).public_send(
                replacement_reader[:getter]
              )
            end
          end
        end

        def define_error_method(target_class, method_name, deprecation_message)
          target_class.define_method(method_name) do |*|
            raise SourceMonitor::DeprecatedOptionError, deprecation_message
          end
        end

        # Parse replacement path into target accessor chain and setter name.
        # When source_prefix matches the replacement prefix, the target is nil
        # (replacement is on the same settings class).
        #
        # "http.proxy" with source_prefix "http" => { target: nil, setter: "proxy=" }
        # "queue_namespace" => { target: nil, setter: "queue_namespace=" }
        # "http.proxy" with source_prefix nil => { target: :http, setter: "proxy=" }
        def replacement_setter_for(replacement, source_prefix = nil)
          return nil unless replacement

          segments = replacement.split(".")
          if segments.length == 1
            { target: nil, setter: :"#{segments.first}=" }
          elsif source_prefix && segments.first == source_prefix
            { target: nil, setter: :"#{segments.last}=" }
          else
            { target: segments.first.to_sym, setter: :"#{segments.last}=" }
          end
        end

        # Parse replacement path into target accessor chain and getter name.
        def replacement_getter_for(replacement, source_prefix = nil)
          return nil unless replacement

          segments = replacement.split(".")
          if segments.length == 1
            { target: nil, getter: segments.first.to_sym }
          elsif source_prefix && segments.first == source_prefix
            { target: nil, getter: segments.last.to_sym }
          else
            { target: segments.first.to_sym, getter: segments.last.to_sym }
          end
        end
      end
    end
  end
end

# Add a helper method to settings classes and Configuration for resolving
# replacement targets. This allows "http.proxy" to resolve as self.http.proxy
# from within a Configuration instance, or as self.proxy from within an
# HTTPSettings instance.
module SourceMonitor
  class Configuration
    private

    def resolve_replacement_target(accessor)
      accessor ? public_send(accessor) : self
    end
  end
end

# Add the same helper to all settings classes so forwarding works
# when the deprecated method is defined on a nested settings class
# and the replacement is on the same class (e.g. "http.old_proxy" -> "http.proxy").
SourceMonitor::Configuration::DeprecationRegistry::SETTINGS_CLASSES.each_value do |class_name|
  klass = SourceMonitor::Configuration.const_get(class_name)
  unless klass.method_defined?(:resolve_replacement_target, false)
    klass.define_method(:resolve_replacement_target) do |accessor|
      accessor ? public_send(accessor) : self
    end
    klass.send(:private, :resolve_replacement_target)
  end
end
