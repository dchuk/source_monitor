---
phase: "02"
plan: "03"
title: "Scrape Candidates Query Object"
status: complete
---

## What Was Built

Extracted the `Source.scrape_candidates` raw SQL subquery into a dedicated `ScrapeCandidatesQuery` query object under `SourceMonitor::Queries`. The raw SQL with string interpolation was replaced with ActiveRecord query methods (`joins`, `group`, `having`, `select`). The public API on `Source.scrape_candidates` is unchanged -- it delegates to the query object. Includes 5 unit tests for the new query object.

## Commits

- `5033a25` refactor(models): extract Source.scrape_candidates to ScrapeCandidatesQuery object

## Tasks Completed

1. **Create ScrapeCandidatesQuery class** - New query object at `lib/source_monitor/queries/scrape_candidates_query.rb` using ActiveRecord `joins`, `group`, `having`, `select` instead of raw SQL string interpolation.
2. **Add autoload declarations** - Created `lib/source_monitor/queries.rb` module file and added `Queries` module autoload in `lib/source_monitor.rb`.
3. **Delegate Source.scrape_candidates** - Replaced 16-line raw SQL method body with single-line delegation to the query object, preserving the same public API.
4. **Write unit tests** - 5 tests covering: below threshold (included), above threshold (excluded), scraping enabled (excluded), inactive (excluded), zero/negative threshold (empty).

## Files Modified

| Action | Path |
|--------|------|
| CREATE | `lib/source_monitor/queries/scrape_candidates_query.rb` |
| CREATE | `lib/source_monitor/queries.rb` |
| MODIFY | `lib/source_monitor.rb` |
| MODIFY | `app/models/source_monitor/source.rb` |
| CREATE | `test/lib/source_monitor/queries/scrape_candidates_query_test.rb` |

## Deviations

- Tests use `SourceMonitor::ItemContent.create!(item: item)` without explicit `feed_word_count` parameter (relying on the `before_save` callback to compute it from `item.content`), matching the existing source_test.rb pattern. Direct `feed_word_count` assignment is overwritten by the callback.
