---
phase: "03"
plan: "03"
title: "Extract Sources Index Metrics & Redirect Validation"
status: complete
---

## What Was Built
Extracted word count average queries from SourcesController#index into SourcesIndexMetrics.word_count_averages. Added ParameterSanitizer.safe_redirect_path for centralized redirect validation.

## Commits
- a6d7148 refactor(controllers): extract sources index metrics and redirect validation

## Tasks Completed
1. Added 5 tests for ParameterSanitizer.safe_redirect_path (valid path, blank, full URL, XSS, sanitization)
2. Added safe_redirect_path class method to ParameterSanitizer
3. Added word_count_averages method to SourcesIndexMetrics with 2 tests
4. Updated SourcesController to use extracted methods, removed private safe_redirect_path

## Files Modified
- app/controllers/source_monitor/sources_controller.rb
- lib/source_monitor/analytics/sources_index_metrics.rb
- lib/source_monitor/security/parameter_sanitizer.rb
- test/lib/source_monitor/analytics/sources_index_metrics_test.rb
- test/lib/source_monitor/security/parameter_sanitizer_test.rb (new)

## Deviations
None.
