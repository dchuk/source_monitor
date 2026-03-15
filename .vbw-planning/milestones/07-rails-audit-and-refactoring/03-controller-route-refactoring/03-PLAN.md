---
phase: "03"
plan: "03"
title: "Extract Sources Index Metrics & Redirect Validation"
wave: 1
depends_on: []
must_haves:
  - "SourcesController#index word count average queries extracted to SourcesIndexMetrics or a new query/presenter method"
  - "safe_redirect_path moved to SourceMonitor::Security::ParameterSanitizer.safe_redirect_path class method"
  - "SourcesController calls ParameterSanitizer.safe_redirect_path instead of inline method"
  - "compute_scrape_candidate_ids remains in controller (it depends on instance variables)"
  - "Tests for ParameterSanitizer.safe_redirect_path cover: valid path, blank, non-path, XSS attempt"
  - "Existing sources_controller tests still pass"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 03: Extract Sources Index Metrics & Redirect Validation

## Objective

Reduce SourcesController complexity by extracting word count average queries into the existing SourcesIndexMetrics object (C4), and moving redirect validation to the ParameterSanitizer service (C10).

## Context

- `app/controllers/source_monitor/sources_controller.rb:50-62` computes `@avg_feed_word_counts` and `@avg_scraped_word_counts` inline
- `SourceMonitor::Analytics::SourcesIndexMetrics` already exists and handles other index metrics -- word count averages belong there
- `safe_redirect_path` (lines 171-176) is a pure function that validates redirect paths -- belongs in `SourceMonitor::Security::ParameterSanitizer`
- `lib/source_monitor/security/parameter_sanitizer.rb` already has `sanitize` method

## Tasks

### Task 1: Write tests for ParameterSanitizer.safe_redirect_path (TDD red)

Add tests to the existing ParameterSanitizer test file:
- Returns path when input starts with "/"
- Returns nil when input is blank
- Returns nil when input is a full URL (not relative path)
- Returns nil when input contains XSS/injection attempts
- Sanitizes input before checking

### Task 2: Add safe_redirect_path to ParameterSanitizer

In `lib/source_monitor/security/parameter_sanitizer.rb`, add class method:
```ruby
def self.safe_redirect_path(raw_value)
  return if raw_value.blank?
  sanitized = sanitize(raw_value.to_s)
  sanitized.start_with?("/") ? sanitized : nil
end
```

### Task 3: Extract word count averages to SourcesIndexMetrics

Add `word_count_averages(source_ids)` method to `SourceMonitor::Analytics::SourcesIndexMetrics` that returns a hash with `:feed` and `:scraped` keys. Update SourcesController#index to call `metrics.word_count_averages(source_ids)` and assign the instance variables from the result.

### Task 4: Update SourcesController

- Replace inline word count queries (lines 50-62) with call to metrics object
- Replace `safe_redirect_path` private method with `SourceMonitor::Security::ParameterSanitizer.safe_redirect_path`
- Remove the `safe_redirect_path` private method

### Task 5: Verify

- `bin/rails test` -- all pass
- `bin/rubocop` -- zero offenses
