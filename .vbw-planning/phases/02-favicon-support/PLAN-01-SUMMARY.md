---
phase: 2
plan: 1
title: "Favicon Infrastructure: Config, Model, Job, and Discovery"
status: complete
tasks_completed: 5
tasks_total: 5
commits:
  - 0a6935f
  - 0e8fd84
  - 9824992
  - 8517238
tests_added: 42
tests_pass: true
rubocop_offenses: 0
deviations: []
---

## What Was Built

- FaviconsSettings configuration class with enabled, fetch_timeout, max_download_size, retry_cooldown_days, allowed_content_types
- Source model `has_one_attached :favicon` with `if defined?(ActiveStorage)` guard
- Favicons::Discoverer implementing /favicon.ico -> HTML link tag parsing -> Google Favicon API cascade
- FaviconFetchJob with early-return guards (missing source, disabled, blank URL, already attached, cooldown)
- Favicons module autoload wired in lib/source_monitor.rb, FaviconsSettings require in configuration.rb

## Files Modified

- `lib/source_monitor/configuration/favicons_settings.rb` -- new settings class with defaults and enabled?
- `lib/source_monitor/configuration.rb` -- added favicons_settings require, attr_reader, initialization
- `app/models/source_monitor/source.rb` -- has_one_attached :favicon with ActiveStorage guard
- `lib/source_monitor/favicons/discoverer.rb` -- multi-strategy favicon discovery with HTML parsing and validation
- `app/jobs/source_monitor/favicon_fetch_job.rb` -- background job with cooldown tracking via metadata JSONB
- `lib/source_monitor.rb` -- Favicons module autoload declaration
- `test/lib/source_monitor/configuration/favicons_settings_test.rb` -- 13 tests for settings
- `test/models/source_monitor/source_favicon_test.rb` -- 3 tests for model attachment
- `test/lib/source_monitor/favicons/discoverer_test.rb` -- 16 tests for discovery cascade
- `test/jobs/source_monitor/favicon_fetch_job_test.rb` -- 10 tests for job guards and behavior
