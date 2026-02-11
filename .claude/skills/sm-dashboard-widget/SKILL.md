---
name: sm-dashboard-widget
description: Creates dashboard widgets with queries, presenters, and Turbo broadcasts for Source Monitor. Use when building dashboard metrics, stats panels, or real-time monitoring displays.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
disable-model-invocation: true
---

# SourceMonitor Dashboard Widget

## Overview

The SourceMonitor dashboard lives at `DashboardController#index` and is composed of widgets: stat cards, recent activity feeds, job queue metrics, fetch schedules, and quick actions. Each widget follows a query-presenter-view pattern with optional Turbo Stream broadcasting for real-time updates.

## Architecture

```
Controller (app/controllers/source_monitor/dashboard_controller.rb)
  |
  v
Queries (lib/source_monitor/dashboard/queries.rb)        -- facade
  |-- StatsQuery           -- single SQL for source counts + item/fetch totals
  |-- RecentActivityQuery  -- UNION ALL across fetch_logs, scrape_logs, items
  |-- UpcomingFetchSchedule -- groups active sources into time-window buckets
  |-- job_metrics           -- delegates to Jobs::SolidQueueMetrics
  |-- quick_actions         -- static QuickAction structs
  |
  v
Presenters
  |-- RecentActivityPresenter  -- maps Event structs to view-model hashes
  |-- QuickActionsPresenter    -- maps QuickAction structs to path-resolved hashes
  |
  v
Views (app/views/source_monitor/dashboard/)
  |-- index.html.erb           -- layout shell with turbo_stream_from
  |-- _stats.html.erb          -- grid of stat cards
  |-- _stat_card.html.erb      -- single stat card partial (collection render)
  |-- _recent_activity.html.erb
  |-- _fetch_schedule.html.erb
  |-- _job_metrics.html.erb
  |
  v
TurboBroadcaster (lib/source_monitor/dashboard/turbo_broadcaster.rb)
  |-- registers event callbacks (after_fetch_completed, after_item_created)
  |-- broadcasts replace_to for stats, recent_activity, fetch_schedule
```

## Creating a New Dashboard Widget

### Step 1: Define the Query

Create a query class under `lib/source_monitor/dashboard/queries/`. Follow the existing pattern:

```ruby
# frozen_string_literal: true

module SourceMonitor
  module Dashboard
    class Queries
      class MyWidgetQuery
        def initialize(reference_time:)
          @reference_time = reference_time
        end

        def call
          # Return a hash, array of structs, or value object
          {
            metric_a: compute_metric_a,
            metric_b: compute_metric_b
          }
        end

        private

        attr_reader :reference_time

        def compute_metric_a
          # Use quoted_table_name for SQL safety
          SourceMonitor::Source.connection.select_value(<<~SQL.squish).to_i
            SELECT COUNT(*)
            FROM #{SourceMonitor::Source.quoted_table_name}
            WHERE some_condition
          SQL
        end

        def compute_metric_b
          SourceMonitor::Item.where("created_at >= ?", reference_time.beginning_of_day).count
        end
      end
    end
  end
end
```

Key patterns:
- Constructor takes `reference_time:` for time-relative queries
- `call` returns the result (hash, array, or value object)
- Use `quoted_table_name` for all SQL references
- Use `connection.exec_query` for multi-column results
- Use `connection.select_value` for single scalar values
- Use ActiveRecord scopes when raw SQL is not needed

### Step 2: Register in the Queries Facade

Add a method in `lib/source_monitor/dashboard/queries.rb`:

```ruby
def my_widget
  cache.fetch(:my_widget) do
    measure(:my_widget) do
      MyWidgetQuery.new(reference_time:).call
    end
  end
end
```

The `cache` prevents duplicate computation within a single request. The `measure` wrapper:
1. Records timing via `ActiveSupport::Notifications.instrument`
2. Publishes gauge metrics via `SourceMonitor::Metrics.gauge`

Add a require at the top of the file:
```ruby
require "source_monitor/dashboard/queries/my_widget_query"
```

### Step 3: Create a Presenter (if needed)

Presenters live in `lib/source_monitor/dashboard/`. They transform query results into view-friendly hashes, resolving route paths using `url_helpers`.

```ruby
# frozen_string_literal: true

module SourceMonitor
  module Dashboard
    class MyWidgetPresenter
      def initialize(data, url_helpers:)
        @data = data
        @url_helpers = url_helpers
      end

      def to_a
        data.map { |item| build_view_model(item) }
      end

      private

      attr_reader :data, :url_helpers

      def build_view_model(item)
        {
          label: item.name,
          value: item.count,
          path: url_helpers.source_path(item.source_id)
        }
      end
    end
  end
end
```

Presenter conventions:
- Constructor takes raw data + `url_helpers:` keyword
- `to_a` returns array of plain hashes for the view
- `url_helpers` comes from `SourceMonitor::Engine.routes.url_helpers`

### Step 4: Wire into the Controller

In `app/controllers/source_monitor/dashboard_controller.rb`:

```ruby
def index
  queries = SourceMonitor::Dashboard::Queries.new
  url_helpers = SourceMonitor::Engine.routes.url_helpers

  # existing assigns...
  @my_widget = MyWidgetPresenter.new(queries.my_widget, url_helpers:).to_a
end
```

### Step 5: Create the View Partial

Create `app/views/source_monitor/dashboard/_my_widget.html.erb`:

```erb
<div id="source_monitor_dashboard_my_widget" class="rounded-lg border border-slate-200 bg-white shadow-sm">
  <div class="border-b border-slate-200 px-5 py-4">
    <h2 class="text-lg font-medium">My Widget</h2>
    <p class="mt-1 text-xs text-slate-500">Description of what this widget shows.</p>
  </div>
  <div class="divide-y divide-slate-100">
    <%% if my_widget.any? %>
      <%% my_widget.each do |item| %>
        <div class="flex items-center justify-between px-5 py-4">
          <div class="text-sm font-medium text-slate-900"><%%= item[:label] %></div>
          <div class="text-sm text-slate-600"><%%= item[:value] %></div>
        </div>
      <%% end %>
    <%% else %>
      <div class="px-5 py-6 text-sm text-slate-500">No data available.</div>
    <%% end %>
  </div>
</div>
```

Important: The outer div must have an `id` prefixed with `source_monitor_dashboard_` for Turbo Stream targeting.

Render in `index.html.erb`:
```erb
<%%= render "my_widget", my_widget: @my_widget %>
```

### Step 6: Add Turbo Stream Broadcasting (optional)

In `lib/source_monitor/dashboard/turbo_broadcaster.rb`, add a broadcast call inside `broadcast_dashboard_updates`:

```ruby
Turbo::StreamsChannel.broadcast_replace_to(
  STREAM_NAME,
  target: "source_monitor_dashboard_my_widget",
  html: render_partial(
    "source_monitor/dashboard/my_widget",
    my_widget: MyWidgetPresenter.new(
      queries.my_widget,
      url_helpers:
    ).to_a
  )
)
```

The broadcaster is triggered by event callbacks registered in `setup!`. Existing triggers:
- `after_fetch_completed` -- fires after each feed fetch
- `after_item_created` -- fires when a new item is persisted

To add a new trigger, register another callback:
```ruby
register_callback(:after_scrape_completed, scrape_callback)
```

### Step 7: Add Metrics Recording

In the `record_metrics` method of `queries.rb`, add a case for your widget:

```ruby
when :my_widget
  SourceMonitor::Metrics.gauge(:dashboard_my_widget_count, result.size)
```

## Existing Widget Reference

### Stat Cards
- Query: `StatsQuery` returns `{ total_sources:, active_sources:, failed_sources:, total_items:, fetches_today: }`
- View: `_stats.html.erb` renders `_stat_card.html.erb` as a collection
- Turbo target: `source_monitor_dashboard_stats`

### Recent Activity
- Query: `RecentActivityQuery` uses UNION ALL across fetch_logs, scrape_logs, items
- Struct: `RecentActivity::Event` (keyword_init Struct)
- Presenter: `RecentActivityPresenter` maps events to `{ label:, description:, status:, type:, time:, path: }`
- View: `_recent_activity.html.erb`
- Turbo target: `source_monitor_dashboard_recent_activity`

### Job Metrics
- Query: `job_metrics` delegates to `Jobs::SolidQueueMetrics.call`
- Returns array of `{ role:, queue_name:, summary: }` hashes
- View: `_job_metrics.html.erb`
- No Turbo broadcasting (refreshed on page load)

### Fetch Schedule
- Query: `UpcomingFetchSchedule` groups sources into time-window buckets
- Struct: `UpcomingFetchSchedule::Group` with `:key, :label, :sources, :window_start, :window_end`
- View: `_fetch_schedule.html.erb`
- Turbo target: `source_monitor_dashboard_fetch_schedule`

### Quick Actions
- Static `QuickAction` structs defined in `Queries::QUICK_ACTIONS`
- Presenter: `QuickActionsPresenter` resolves route names to paths
- View: inline in `index.html.erb`

## Data Structures

### RecentActivity::Event (Struct)
```ruby
Struct.new(
  :type, :id, :occurred_at, :success, :items_created,
  :items_updated, :scraper_adapter, :item_title, :item_url,
  :source_name, :source_id, keyword_init: true
)
```

### UpcomingFetchSchedule::Group (Struct)
```ruby
Struct.new(
  :key, :label, :min_minutes, :max_minutes,
  :window_start, :window_end, :include_unscheduled, :sources,
  keyword_init: true
)
```

### QuickAction (Struct)
```ruby
Struct.new(:label, :description, :route_name, keyword_init: true)
```

## Turbo Stream Setup

The dashboard view subscribes to the broadcast channel:
```erb
<%%= turbo_stream_from SourceMonitor::Dashboard::TurboBroadcaster::STREAM_NAME %>
```

Stream name: `"source_monitor_dashboard"`

The broadcaster uses `DashboardController.render(partial:, locals:)` to render partials outside of a request context.

## Caching

The `Queries` class uses an in-memory `Cache` (simple hash store) scoped to the instance. Each `Queries.new` gets a fresh cache, so data is fresh per request but not duplicated within one request.

## File Locations

| Component | Path |
|-----------|------|
| Controller | `app/controllers/source_monitor/dashboard_controller.rb` |
| Queries facade | `lib/source_monitor/dashboard/queries.rb` |
| StatsQuery | `lib/source_monitor/dashboard/queries/stats_query.rb` |
| RecentActivityQuery | `lib/source_monitor/dashboard/queries/recent_activity_query.rb` |
| UpcomingFetchSchedule | `lib/source_monitor/dashboard/upcoming_fetch_schedule.rb` |
| RecentActivity::Event | `lib/source_monitor/dashboard/recent_activity.rb` |
| RecentActivityPresenter | `lib/source_monitor/dashboard/recent_activity_presenter.rb` |
| QuickAction | `lib/source_monitor/dashboard/quick_action.rb` |
| QuickActionsPresenter | `lib/source_monitor/dashboard/quick_actions_presenter.rb` |
| TurboBroadcaster | `lib/source_monitor/dashboard/turbo_broadcaster.rb` |
| Views | `app/views/source_monitor/dashboard/` |

## Testing

Dashboard queries should be tested with integration tests that verify SQL correctness against real records. See `test/lib/source_monitor/dashboard/` for existing test patterns.

Presenters can be unit-tested with mock url_helpers:
```ruby
class FakeUrlHelpers
  def source_path(id) = "/source_monitor/sources/#{id}"
  def fetch_log_path(id) = "/source_monitor/fetch_logs/#{id}"
end
```
