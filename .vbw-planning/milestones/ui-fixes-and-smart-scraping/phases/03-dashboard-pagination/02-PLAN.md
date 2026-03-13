---
phase: "03"
plan: "02"
title: "Dashboard Schedule Refactor with AR Scopes and Per-Bucket Pagination"
wave: 1
depends_on: []
must_haves:
  - "UpcomingFetchSchedule uses AR scopes instead of in-memory grouping"
  - "Each schedule bucket is independently paginated"
  - "Turbo Frames wrap each bucket for independent pagination"
  - "Empty buckets are hidden"
  - "Dashboard still renders correctly with 0, 1, and 100+ sources"
---

# Plan 02: Dashboard Schedule Refactor with AR Scopes and Per-Bucket Pagination

## Goal

Replace the in-memory grouping in `UpcomingFetchSchedule` with ActiveRecord scope-based bucket queries. Add per-bucket pagination using the existing `Paginator` (using `has_next_page`/`has_previous_page` -- not total_count, which is plan 01's work). Wrap each bucket in a Turbo Frame for independent pagination.

## Task 1: Refactor UpcomingFetchSchedule to use AR scopes

**What:** Replace the current approach (load ALL active sources, iterate in Ruby to assign to groups) with per-bucket AR queries using `WHERE next_fetch_at` range conditions.

**Files to modify:**
- `lib/source_monitor/dashboard/upcoming_fetch_schedule.rb`

**Implementation details:**
- Keep `INTERVAL_DEFINITIONS` and `Group` struct (add `page`, `has_next_page`, `has_previous_page` fields to Group)
- Remove `build_groups`, `scheduled_sources`, `unscheduled_sources`, `definition_for`, `minutes_until`, `sort_sources` methods
- Replace with `build_groups` that iterates INTERVAL_DEFINITIONS, builds an AR scope per bucket, paginates each:
  - Bucket "0-30": `scope.where(next_fetch_at: reference_time..(reference_time + 30.minutes))`
  - Bucket "30-60": `scope.where(next_fetch_at: (reference_time + 30.minutes)..(reference_time + 60.minutes))`
  - etc.
  - Bucket "240+": `scope.where(next_fetch_at: (reference_time + 240.minutes)..)`  + `scope.where(next_fetch_at: nil)` combined via `.or()`
- Accept `pages` parameter (hash of `{ bucket_key => page_number }`) in initializer, default `{}`
- Per bucket, use `Paginator.new(scope: bucket_scope.order(:next_fetch_at, :name), page: pages[key] || 1, per_page: per_page)` where `per_page` defaults to 10
- Store pagination results in Group struct: `sources`, `page`, `has_next_page`, `has_previous_page`
- Hide empty buckets: only return groups where the bucket scope has at least one record (use `.exists?` to avoid loading data for empty buckets)

**Acceptance criteria:**
- No full-table load -- each bucket does its own scoped query
- Empty buckets are excluded from the groups array
- Each group has `page`, `has_next_page`, `has_previous_page` fields
- `groups` method returns only non-empty groups

## Task 2: Update DashboardController to pass bucket page params

**What:** Modify the dashboard controller to extract per-bucket page params from the request and pass them to UpcomingFetchSchedule.

**Files to modify:**
- `app/controllers/source_monitor/dashboard_controller.rb`

**Implementation details:**
- Extract `schedule_pages` from params: `params.fetch(:schedule_pages, {}).permit!.to_h`
- Pass to `UpcomingFetchSchedule.new(scope: ..., pages: schedule_pages)`
- Pass `schedule_pages` to the view as `@schedule_pages` so the partial can build links

**Acceptance criteria:**
- Controller passes page params per bucket
- Default behavior (no params) shows page 1 for all buckets

## Task 3: Update fetch_schedule partial with Turbo Frames and pagination

**What:** Wrap each schedule bucket in a Turbo Frame with a unique ID. Add prev/next pagination controls per bucket. Build inline pagination (simpler than the shared partial since we use has_next/previous without total count).

**Files to modify:**
- `app/views/source_monitor/dashboard/_fetch_schedule.html.erb`

**Implementation details:**
- Wrap each group in `turbo_frame_tag "source_monitor_schedule_#{group.key}"`
- After the source table, render pagination controls (Previous/Next) if group has more than one page
- Pagination links target the dashboard path with `schedule_pages[bucket_key]=N` param
- Each link sets `data-turbo-frame` to the bucket's frame ID so only that section reloads
- Update the group header badge to show page info: "X sources" (count badge stays, since we don't have total without plan 01)
- When a bucket is empty (0 sources), it's already excluded from groups by Task 1
- The overall schedule header ("Upcoming Fetch Schedule") stays outside all frames so it never disappears

**Acceptance criteria:**
- Each bucket is independently scrollable via Turbo Frames
- Navigating one bucket doesn't affect other buckets or the rest of the dashboard
- Pagination controls only show when the bucket has multiple pages
- Empty buckets don't render at all

## Task 4: Update Dashboard::Queries to pass pages param through

**What:** Modify `Queries#upcoming_fetch_schedule` to accept and forward the pages parameter.

**Files to modify:**
- `lib/source_monitor/dashboard/queries.rb`

**Implementation details:**
- Change `upcoming_fetch_schedule` to accept `pages: {}` keyword argument
- Forward to `UpcomingFetchSchedule.new(scope: ..., pages: pages)`
- Update the cache key to include pages so different page views don't return stale cached data: `[:upcoming_fetch_schedule, pages]`

**Acceptance criteria:**
- Different page params produce different cache entries
- Default (no pages) still works as before

## Task 5: Write tests for refactored UpcomingFetchSchedule

**What:** Add/update tests for the scope-based schedule with pagination.

**Files to create:**
- `test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb`

**Test cases:**
- `test "groups sources into correct time buckets using AR scopes"` -- Create sources with different `next_fetch_at` values, verify they land in correct buckets
- `test "hides empty buckets"` -- Create sources only in one bucket, verify other buckets are absent from groups
- `test "paginates within a bucket"` -- Create 15 sources in one bucket (per_page 10), verify page 1 has 10, page 2 has 5
- `test "includes unscheduled sources in the 240+ bucket"` -- Source with nil next_fetch_at lands in last bucket
- `test "respects per-bucket page params"` -- Pass `pages: { "0-30" => 2 }`, verify second page loads

**Acceptance criteria:**
- All tests pass with thread-based parallelism
- Tests create their own scoped data to avoid cross-test contamination

## File Disjointness (Wave 1)

This plan modifies:
- `lib/source_monitor/dashboard/upcoming_fetch_schedule.rb`
- `lib/source_monitor/dashboard/queries.rb`
- `app/controllers/source_monitor/dashboard_controller.rb`
- `app/views/source_monitor/dashboard/_fetch_schedule.html.erb`
- `test/lib/source_monitor/dashboard/upcoming_fetch_schedule_test.rb` (NEW)

No overlap with Plan 01 (paginator lib, shared partial, application_helper) or Plan 04 (stats query, stats partial).
