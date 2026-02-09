# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

# Turbo is loaded via turbo-rails gem
# Stimulus is loaded via stimulus-rails gem

# Don't auto-load application.js since we're using the SourceMonitor engine's JavaScript
# The engine JavaScript is loaded separately via source_monitor/application
