# Dashboard Patterns Reference

## Query Patterns

### Single-Value Aggregation (StatsQuery pattern)
Use `connection.select_value` for scalar results:

```ruby
def total_items_count
  SourceMonitor::Item.connection.select_value(
    "SELECT COUNT(*) FROM #{SourceMonitor::Item.quoted_table_name}"
  ).to_i
end
```

### Multi-Column Aggregation
Use `connection.exec_query` with conditional aggregation:

```ruby
def source_counts
  @source_counts ||= begin
    SourceMonitor::Source.connection.exec_query(<<~SQL.squish).first || {}
      SELECT
        COUNT(*) AS total_sources,
        SUM(CASE WHEN active THEN 1 ELSE 0 END) AS active_sources,
        SUM(CASE WHEN (failure_count > 0) THEN 1 ELSE 0 END) AS failed_sources
      FROM #{SourceMonitor::Source.quoted_table_name}
    SQL
  end
end
```

### UNION ALL Cross-Table Query (RecentActivityQuery pattern)
Combine events from multiple tables into a unified feed:

```ruby
def unified_sql_template
  <<~SQL
    SELECT resource_type, resource_id, occurred_at, ...
    FROM (
      #{fetch_log_sql}
      UNION ALL
      #{scrape_log_sql}
      UNION ALL
      #{item_sql}
    ) AS dashboard_events
    WHERE occurred_at IS NOT NULL
    ORDER BY occurred_at DESC
    LIMIT ?
  SQL
end
```

Each sub-query must:
- Use the same column names/count (pad with `NULL AS column_name`)
- Use `quoted_table_name` for all table references
- Use string constants for type discriminators: `'fetch_log' AS resource_type`

Sanitize with:
```ruby
ActiveRecord::Base.send(:sanitize_sql_array, [sql_template, limit])
```

### Time-Window Grouping (UpcomingFetchSchedule pattern)
Group records into defined time buckets relative to a reference time:

```ruby
INTERVAL_DEFINITIONS = [
  { key: "0-30",  label: "Within 30 minutes", min_minutes: 0,   max_minutes: 30 },
  { key: "30-60", label: "30-60 minutes",     min_minutes: 30,  max_minutes: 60 },
  # ...
].freeze

def definition_for(next_fetch_at)
  minutes = (next_fetch_at - reference_time) / 60.0
  INTERVAL_DEFINITIONS.find do |d|
    minutes >= d[:min_minutes] && (d[:max_minutes].nil? || minutes < d[:max_minutes])
  end
end
```

### ActiveRecord Scope Query
For simpler queries, use ActiveRecord directly:

```ruby
def fetches_today_count
  SourceMonitor::FetchLog.where("started_at >= ?", start_of_day).count
end
```

## Presenter Patterns

### Collection Presenter
Transforms an array of domain objects into view-model hashes:

```ruby
class RecentActivityPresenter
  def initialize(events, url_helpers:)
    @events = events
    @url_helpers = url_helpers
  end

  def to_a
    events.map { |event| build_view_model(event) }
  end

  private

  attr_reader :events, :url_helpers

  def build_view_model(event)
    case event.type
    when :fetch_log then fetch_event(event)
    when :item      then item_event(event)
    else                  fallback_event(event)
    end
  end

  def fetch_event(event)
    {
      label: "Fetch ##{event.id}",
      description: "#{event.items_created.to_i} created",
      status: event.success? ? :success : :failure,
      type: :fetch,
      time: event.occurred_at,
      path: url_helpers.fetch_log_path(event.id)
    }
  end
end
```

### Static Actions Presenter
Resolves route names to actual paths:

```ruby
class QuickActionsPresenter
  def initialize(actions, url_helpers:)
    @actions = actions
    @url_helpers = url_helpers
  end

  def to_a
    actions.map do |action|
      {
        label: action.label,
        description: action.description,
        path: url_helpers.public_send(action.route_name)
      }
    end
  end
end
```

## Turbo Stream Broadcast Patterns

### Stream Subscription (in view)
```erb
<%= turbo_stream_from SourceMonitor::Dashboard::TurboBroadcaster::STREAM_NAME %>
```

### Broadcasting a Replace
```ruby
Turbo::StreamsChannel.broadcast_replace_to(
  STREAM_NAME,                                    # channel name
  target: "source_monitor_dashboard_stats",       # DOM element id
  html: render_partial(                           # rendered HTML
    "source_monitor/dashboard/stats",
    stats: queries.stats
  )
)
```

### Rendering Partials Outside Request Context
```ruby
def render_partial(partial, locals)
  SourceMonitor::DashboardController.render(
    partial:,
    locals:
  )
end
```

### Event Callback Registration
```ruby
def setup!
  return unless turbo_streams_available?

  register_callback(:after_fetch_completed, fetch_callback)
  register_callback(:after_item_created, item_callback)
end

def register_callback(name, callback)
  callbacks = SourceMonitor.config.events.callbacks_for(name)
  return if callbacks.include?(callback)

  SourceMonitor.config.events.public_send(name, callback)
end
```

### Guard Against Missing Turbo
```ruby
def turbo_streams_available?
  defined?(Turbo::StreamsChannel)
end
```

## View Patterns

### Card Container
```erb
<div id="source_monitor_dashboard_my_widget"
     class="rounded-lg border border-slate-200 bg-white shadow-sm">
  <div class="border-b border-slate-200 px-5 py-4">
    <h2 class="text-lg font-medium">Title</h2>
    <p class="mt-1 text-xs text-slate-500">Subtitle.</p>
  </div>
  <div class="divide-y divide-slate-100">
    <!-- content rows -->
  </div>
</div>
```

### Stat Card (Collection Render)
```erb
<div class="grid gap-5 sm:grid-cols-2 xl:grid-cols-5">
  <%= render partial: "stat_card", collection: [
    { label: "Sources", value: stats[:total_sources], caption: "Total registered" },
    { label: "Active",  value: stats[:active_sources], caption: "Fetching on schedule" }
  ] %>
</div>
```

Each stat card:
```erb
<div class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm">
  <dt class="text-xs font-medium uppercase tracking-wide text-slate-500"><%= stat_card[:label] %></dt>
  <dd class="mt-2 text-3xl font-semibold text-slate-900"><%= value %></dd>
  <p class="mt-1 text-xs text-slate-500"><%= stat_card[:caption] %></p>
</div>
```

### Status Badge
```erb
<span class="inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold
  <%= event[:status] == :success ? 'bg-green-100 text-green-700' : 'bg-rose-100 text-rose-700' %>">
  <%= event[:status] == :success ? "Success" : "Failure" %>
</span>
```

### Empty State
```erb
<% if data.any? %>
  <!-- content -->
<% else %>
  <div class="px-5 py-6 text-sm text-slate-500">
    No data available yet.
  </div>
<% end %>
```

### Dashboard Layout Grid
The dashboard uses a 3-column grid at large breakpoints:
```erb
<section class="grid gap-6 lg:grid-cols-3">
  <div class="lg:col-span-2 space-y-6">
    <!-- main content (recent activity, fetch schedule) -->
  </div>
  <div class="space-y-6">
    <!-- sidebar (job metrics, quick actions) -->
  </div>
</section>
```

## Metrics Integration

Every query method in the facade emits:
- `dashboard_{name}_duration_ms` -- execution time gauge
- `dashboard_{name}_last_run_at_epoch` -- timestamp of last execution
- Widget-specific gauges (e.g., `dashboard_stats_total_sources`)

```ruby
def measure(name, metadata = {})
  started_at = monotonic_time
  result = yield
  duration_ms = ((monotonic_time - started_at) * 1000.0).round(2)

  ActiveSupport::Notifications.instrument("source_monitor.dashboard.#{name}", ...)
  SourceMonitor::Metrics.gauge(:"dashboard_#{name}_duration_ms", duration_ms)

  result
end
```

## Naming Conventions

| Layer | Naming Pattern | Example |
|-------|----------------|---------|
| Query class | `{Widget}Query` | `StatsQuery` |
| Presenter | `{Widget}Presenter` | `RecentActivityPresenter` |
| Struct | `{Widget}::Event` or `{Widget}::Group` | `RecentActivity::Event` |
| View partial | `_snake_case.html.erb` | `_recent_activity.html.erb` |
| Turbo target ID | `source_monitor_dashboard_{snake_case}` | `source_monitor_dashboard_stats` |
| Metric name | `dashboard_{snake_case}_{metric}` | `dashboard_stats_total_sources` |
| Notification | `source_monitor.dashboard.{name}` | `source_monitor.dashboard.stats` |
