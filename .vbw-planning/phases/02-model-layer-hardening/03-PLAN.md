---
phase: "02"
plan: "03"
title: "Scrape Candidates Query Object Extraction"
wave: 1
depends_on: []
must_haves:
  - "Source.scrape_candidates extracted to ScrapeCandidatesQuery class"
  - "Query object follows existing StatsQuery pattern (initialize with params, call returns relation)"
  - "Source.scrape_candidates delegates to query object (backward compatible)"
  - "Raw SQL subquery replaced with ActiveRecord query methods"
  - "Existing scrape_candidates tests pass unchanged"
  - "New unit tests for ScrapeCandidatesQuery"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 03: Scrape Candidates Query Object Extraction

## Objective

Extract `Source.scrape_candidates` raw SQL subquery into a dedicated Query Object, following the existing `StatsQuery` pattern and eliminating inline raw SQL from the Source model.

## Context

- `@app/models/source_monitor/source.rb` -- `scrape_candidates` class method (lines 64-80) contains raw SQL subquery with string interpolation
- `@lib/source_monitor/dashboard/queries/stats_query.rb` -- existing query object pattern to follow
- The raw SQL joins items and item_contents tables, groups by source_id, filters by AVG(feed_word_count) < threshold
- This is the only raw SQL query method on the Source model (the ransackers use Arel.sql but are a Ransack convention)

### Current Implementation

```ruby
def scrape_candidates(threshold: SourceMonitor.config.scraping.scrape_recommendation_threshold)
  threshold_value = threshold.to_i
  return none if threshold_value <= 0
  active
    .where(scraping_enabled: false)
    .where("#{table_name}.id IN (SELECT i.source_id FROM #{Item.table_name} i ...)")
end
```

## Tasks

### Task 1: Create ScrapeCandidatesQuery class

**Files:** `lib/source_monitor/queries/scrape_candidates_query.rb` (new file)

Create query object following project conventions:

```ruby
# frozen_string_literal: true

module SourceMonitor
  module Queries
    class ScrapeCandidatesQuery
      def initialize(threshold: SourceMonitor.config.scraping.scrape_recommendation_threshold)
        @threshold = threshold.to_i
      end

      def call
        return SourceMonitor::Source.none if @threshold <= 0

        SourceMonitor::Source.active
          .where(scraping_enabled: false)
          .where(id: source_ids_below_threshold)
      end

      private

      def source_ids_below_threshold
        SourceMonitor::Item
          .joins(:item_content)
          .where.not(SourceMonitor::ItemContent.table_name => { feed_word_count: nil })
          .group(:source_id)
          .having("AVG(#{SourceMonitor::ItemContent.table_name}.feed_word_count) < ?", @threshold)
          .select(:source_id)
      end
    end
  end
end
```

**Key improvements:**
- Replaces raw SQL string interpolation with ActiveRecord `joins`, `group`, `having`, `select`
- Uses parameterized `?` for threshold instead of string interpolation
- `where(id: subquery)` generates `WHERE id IN (SELECT ...)` via ActiveRecord

**Tests:** New test file
**Acceptance:** Returns same results as original implementation

### Task 2: Add autoload declarations

**Files:** `lib/source_monitor.rb`, `lib/source_monitor/queries.rb` (new file)

Create module file `lib/source_monitor/queries.rb`:

```ruby
# frozen_string_literal: true

module SourceMonitor
  module Queries
    autoload :ScrapeCandidatesQuery, "source_monitor/queries/scrape_candidates_query"
  end
end
```

Add autoload in `lib/source_monitor.rb` (in the autoload section):

```ruby
autoload :Queries, "source_monitor/queries"
```

**Acceptance:** `SourceMonitor::Queries::ScrapeCandidatesQuery` is loadable

### Task 3: Delegate Source.scrape_candidates to query object

**Files:** `app/models/source_monitor/source.rb`

Replace the existing `scrape_candidates` method body (lines 64-80) with:

```ruby
def scrape_candidates(threshold: SourceMonitor.config.scraping.scrape_recommendation_threshold)
  SourceMonitor::Queries::ScrapeCandidatesQuery.new(threshold:).call
end
```

This keeps the same public API -- existing callers don't need to change.

**Tests:** Existing tests should pass unchanged
**Acceptance:** `Source.scrape_candidates` returns identical results

### Task 4: Write unit tests for ScrapeCandidatesQuery

**Files:** `test/lib/source_monitor/queries/scrape_candidates_query_test.rb` (new file)

Tests:

1. `test "returns sources with avg feed word count below threshold"` -- create source with items having low word count ItemContent, query with threshold above avg, assert source included
2. `test "excludes sources above threshold"` -- create source with items having high word count, query with low threshold, assert source excluded
3. `test "excludes sources with scraping enabled"` -- create source with scraping_enabled: true and low word count, assert excluded
4. `test "excludes inactive sources"` -- create inactive source with low word count, assert excluded
5. `test "returns none for zero or negative threshold"` -- assert empty relation

Use `create_source!` factory + create items with ItemContent records.

**Acceptance:** All 5 tests pass

## Files

| Action | Path |
|--------|------|
| CREATE | `lib/source_monitor/queries/scrape_candidates_query.rb` |
| CREATE | `lib/source_monitor/queries.rb` |
| MODIFY | `lib/source_monitor.rb` |
| MODIFY | `app/models/source_monitor/source.rb` |
| CREATE | `test/lib/source_monitor/queries/scrape_candidates_query_test.rb` |

## Verification

```bash
bin/rails test test/lib/source_monitor/queries/scrape_candidates_query_test.rb
bin/rails test test/models/source_monitor/source_test.rb
bin/rubocop lib/source_monitor/queries/ app/models/source_monitor/source.rb
```

## Success Criteria

- Raw SQL removed from Source.scrape_candidates
- Query object uses ActiveRecord methods with parameterized queries
- Public API unchanged (backward compatible)
- All existing + new tests pass
- Zero RuboCop offenses
