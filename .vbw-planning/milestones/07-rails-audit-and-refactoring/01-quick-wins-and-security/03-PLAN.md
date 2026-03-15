---
phase: "01"
plan: "03"
title: "View & Helper Extraction"
wave: 1
depends_on: []
must_haves:
  - "Scrape status badge logic in items/index.html.erb replaced with helper call"
  - "compact_blank fallback pattern extracted to shared helper (used in 3 view locations)"
  - "Toast delay constants centralized and documented"
---

## Tasks

### Task 1: Extract scrape status badge from items/index.html.erb to helper (V2)
**Files:** `app/views/source_monitor/items/index.html.erb`, `app/helpers/source_monitor/application_helper.rb`, `test/helpers/source_monitor/application_helper_test.rb`
**Action:**
The items index view (lines 103-113) has inline scrape status badge logic:
```erb
<% status_label, status_classes =
     case item.scrape_status
     when "success"
       ["Scraped", "bg-green-100 text-green-700"]
     when "failed"
       ["Failed", "bg-rose-100 text-rose-700"]
     when "pending"
       ["Pending", "bg-amber-100 text-amber-700"]
     else
       ["Not Scraped", "bg-slate-100 text-slate-600"]
     end %>
```
`ApplicationHelper` already has `item_scrape_status_badge` (line 165) which does this same mapping via `ITEM_SCRAPE_STATUS_LABELS` and `async_status_badge`. Replace the inline case statement with:
```erb
<% badge = item_scrape_status_badge(item: item, source: @source, show_spinner: false) %>
<span class="inline-flex items-center rounded-full px-3 py-1 font-semibold <%= badge[:classes] %>"><%= badge[:label] %></span>
```
This eliminates duplicated badge logic and ensures consistency with the helper.

**Tests:** Existing helper tests for `item_scrape_status_badge` cover the mapping. No new tests needed. Verify the items index renders correctly with existing controller tests.
**Acceptance:** No inline case statement for scrape badges in items/index.html.erb. Helper is used instead.

### Task 2: Extract compact_blank fallback to shared helper (V10)
**Files:** `app/helpers/source_monitor/application_helper.rb`, `app/views/source_monitor/sources/index.html.erb`, `app/views/source_monitor/sources/_row.html.erb`, `test/helpers/source_monitor/application_helper_test.rb`
**Action:**
The `compact_blank` fallback pattern appears 3 times in views:
1. `sources/index.html.erb` line 65-69 (clear search query)
2. `sources/index.html.erb` line 101-105 (clear filter query)
3. `sources/_row.html.erb` line 24 (delete query)

Note: `ApplicationHelper#fetch_interval_bucket_query` (line 65-69) already has this same pattern. Extract a helper method:
```ruby
def compact_blank_hash(hash)
  return {} if hash.blank?

  if hash.respond_to?(:compact_blank)
    hash.compact_blank
  else
    hash.reject { |_key, value| value.respond_to?(:blank?) ? value.blank? : value.nil? }
  end
end
```
Add this as a public method in `ApplicationHelper` (it's used in views).

Then replace all 3 view occurrences and the 1 helper occurrence with `compact_blank_hash(query)`.

**View replacements:**

In `sources/index.html.erb` line 65-69, replace:
```erb
<% clear_search_query = if clear_search_query.respond_to?(:compact_blank)
  clear_search_query.compact_blank
else
  clear_search_query.reject { |_key, value| value.respond_to?(:blank?) ? value.blank? : value.nil? }
end %>
```
with:
```erb
<% clear_search_query = compact_blank_hash(clear_search_query) %>
```

In `sources/index.html.erb` lines 101-105, replace similarly:
```erb
<% clear_query = compact_blank_hash(clear_query) %>
```

In `sources/_row.html.erb` line 24, replace:
```erb
<% delete_query = delete_query.respond_to?(:compact_blank) ? delete_query.compact_blank : delete_query.reject { |_key, value| value.respond_to?(:blank?) ? value.blank? : value.nil? } if delete_query.present? %>
```
with:
```erb
<% delete_query = compact_blank_hash(delete_query) if delete_query.present? %>
```

In `application_helper.rb` `fetch_interval_bucket_query`, replace lines 65-69:
```ruby
if query.respond_to?(:compact_blank)
  query.compact_blank
else
  query.reject { |_key, value| value.respond_to?(:blank?) ? value.blank? : value.nil? }
end
```
with:
```ruby
compact_blank_hash(query)
```

**Tests:** Test `compact_blank_hash` with a hash containing blank values, nil values, and non-blank values. Test with a hash that responds to `compact_blank` and one that doesn't.
**Acceptance:** No inline `compact_blank` fallback patterns remain in views or helpers. All 4 occurrences use the new helper.

### Task 3: Centralize toast delay constants (V11)
**Files:** `app/controllers/source_monitor/application_controller.rb`, `app/assets/javascripts/source_monitor/controllers/notification_controller.js`
**Action:**
Toast delay constants are already centralized in `ApplicationController`:
```ruby
TOAST_DURATION_DEFAULT = 5000
TOAST_DURATION_ERROR = 6000
```
And the JS notification controller has its own defaults:
```javascript
delay: { default: 5000, type: Number }
```
with a special case at line 40-41:
```javascript
if (level === "error" && this.delayValue === 5000) {
  this.delayValue = 10000;
}
```

The Ruby side is already centralized (one `toast_delay_for` method). The JS side has a mismatch: Ruby sends error delay as 6000ms, but JS overrides 5000→10000 for errors. Since the Ruby `toast_delay_for(:error)` already sends 6000ms (not the default 5000), the JS `if` condition on line 40 never triggers — the delay value is already 6000, not 5000.

This means the JS error override is dead code. Remove lines 40-42 from `notification_controller.js`:
```javascript
if (level === "error" && this.delayValue === 5000) {
  this.delayValue = 10000;
}
```

Add a comment above the Ruby constants to document the contract:
```ruby
# Toast display durations in milliseconds. These values are passed to the
# Stimulus notification_controller via data-notification-delay-value.
TOAST_DURATION_DEFAULT = 5000
TOAST_DURATION_ERROR = 6000
```

After JS change, run `yarn build` to rebuild the bundled JS.

**Tests:** Existing `toast_delay_for` tests in `application_controller_test.rb` already cover the Ruby side. No new tests needed. Verify notification controller still works with existing system tests.
**Acceptance:** Dead JS code removed. Toast constants documented. `yarn build` succeeds.
