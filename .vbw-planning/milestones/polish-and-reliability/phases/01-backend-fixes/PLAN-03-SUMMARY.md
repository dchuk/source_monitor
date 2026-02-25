---
phase: 1
plan: 3
title: "Remove Default Scrape Limit"
status: complete
tasks_completed: 4
commits:
  - cadbf7c
  - 4ba6819
  - 9ba441c
tests_added: 3
tests_pass: 35
rubocop_offenses: 0
deviations: none
---

## What Was Built

Removed the default per-source scrape limit (`max_in_flight_per_source`) from 25 to nil. Solid Queue's worker pool provides natural backpressure. Users who want a cap can still set `config.scraping.max_in_flight_per_source` explicitly.

## Files Modified

- `lib/source_monitor/configuration/scraping_settings.rb` — DEFAULT_MAX_IN_FLIGHT changed from 25 to nil
- `test/lib/source_monitor/scraping/enqueuer_test.rb` — added nil-default rate-limit bypass test
- `test/lib/source_monitor/scraping/bulk_result_presenter_test.rb` — added nil/explicit limit message tests
