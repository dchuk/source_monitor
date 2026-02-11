---
name: caching-strategies
description: Implements Rails caching patterns for performance optimization. Use when adding fragment caching, Russian doll caching, low-level caching, HTTP caching with ETags, cache invalidation, or when user mentions caching, performance, cache keys, or Solid Cache.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Caching Strategies for Rails 8

## Overview

Rails provides multiple caching layers:
- **HTTP caching**: ETags and `fresh_when` for 304 Not Modified
- **Fragment caching**: Cache view partials
- **Russian doll caching**: Nested cache fragments with `touch: true`
- **Low-level caching**: Cache arbitrary data with `Rails.cache.fetch`
- **Collection caching**: Efficient cached rendering of collections
- **Solid Cache**: Database-backed caching (Rails 8 default, no Redis)

## Cache Store Options

| Store | Use Case |
|-------|----------|
| `:memory_store` | Development |
| `:solid_cache_store` | Production (Rails 8 default) |
| `:redis_cache_store` | Production (if Redis available) |
| `:null_store` | Testing |

```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store

# config/environments/development.rb
config.cache_store = :memory_store
```

Enable caching in development:
```bash
bin/rails dev:cache
```

## HTTP Caching (ETags / fresh_when)

Use conditional GET to send 304 Not Modified when content has not changed.

```ruby
class EventsController < ApplicationController
  def show
    @event = current_account.events.find(params[:id])
    fresh_when @event
  end

  def index
    @events = current_account.events.recent
    fresh_when @events
  end
end
```

### Composite ETags

```ruby
def show
  @event = current_account.events.find(params[:id])
  fresh_when [@event, Current.user]
end
```

### With stale? for JSON

```ruby
class Api::EventsController < Api::BaseController
  def show
    @event = current_account.events.find(params[:id])
    if stale?(@event)
      render json: @event
    end
  end
end
```

## Fragment Caching

```erb
<%# app/views/events/_event.html.erb %>
<% cache event do %>
  <article class="event-card">
    <h3><%= event.name %></h3>
    <p><%= event.description %></p>
    <time><%= l(event.event_date, format: :long) %></time>
  </article>
<% end %>
```

### Custom Cache Keys

```erb
<% cache [event, "v2"] do %>
  ...
<% end %>

<% cache [event, current_user] do %>
  ...
<% end %>
```

## Russian Doll Caching

Nested caches with automatic invalidation through `touch: true`:

```ruby
# app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :event, touch: true
end
```

```erb
<% cache @event do %>
  <h1><%= @event.name %></h1>
  <% @event.comments.each do |comment| %>
    <% cache comment do %>
      <%= render comment %>
    <% end %>
  <% end %>
<% end %>
```

When a comment is updated, `touch: true` cascades up through `updated_at` timestamps, invalidating all parent caches automatically.

## Collection Caching

```erb
<%# Caches each item individually, multi-read from cache store %>
<%= render partial: "events/event", collection: @events, cached: true %>
```

## Low-Level Caching

```ruby
Rails.cache.fetch("stats/#{Date.current}", expires_in: 1.hour) do
  { total_events: Event.count, total_revenue: Order.sum(:total_cents) }
end
```

### In Models

```ruby
class Board < ApplicationRecord
  def statistics
    Rails.cache.fetch([self, "statistics"], expires_in: 1.hour) do
      {
        total_cards: cards.count,
        completed_cards: cards.joins(:closure).count,
        total_comments: cards.joins(:comments).count
      }
    end
  end
end
```

### With Race Condition Protection

```ruby
Rails.cache.fetch([self, "stats"], expires_in: 1.hour, race_condition_ttl: 10.seconds) do
  expensive_operation
end
```

## Cache Invalidation

### Key-Based (Automatic)

Cache keys include `updated_at`, so updates automatically expire old entries.

### Touch Cascade

```ruby
class Card < ApplicationRecord
  belongs_to :board, touch: true  # Updates board.updated_at
end

class Comment < ApplicationRecord
  belongs_to :card, touch: true   # Updates card.updated_at -> board.updated_at
end
```

### Manual Invalidation

```ruby
class Event < ApplicationRecord
  after_commit :invalidate_caches

  private

  def invalidate_caches
    Rails.cache.delete([self, "statistics"])
    Rails.cache.delete("featured_events")
  end
end
```

### Sweeper Pattern

```ruby
class CacheSweeper
  def self.clear_board_caches(board)
    Rails.cache.delete([board, "statistics"])
    Rails.cache.delete([board, "card_distribution"])
  end
end
```

## Counter Caching

```ruby
# Migration
add_column :events, :vendors_count, :integer, default: 0, null: false

# Model
class Vendor < ApplicationRecord
  belongs_to :event, counter_cache: true
end

# Usage (no query needed)
event.vendors_count
```

## Cache Warming

```ruby
class CacheWarmerJob < ApplicationJob
  queue_as :low

  def perform(account)
    account.boards.find_each do |board|
      board.statistics
      board.card_distribution
    end
  end
end
```

## Testing Caching

```ruby
# test/test_helper.rb (enable caching for specific tests)
class ActiveSupport::TestCase
  def with_caching(&block)
    caching = ActionController::Base.perform_caching
    ActionController::Base.perform_caching = true
    Rails.cache.clear
    yield
  ensure
    ActionController::Base.perform_caching = caching
  end
end
```

### Testing Touch Cascade

```ruby
# test/models/card_test.rb
require "test_helper"

class CardCachingTest < ActiveSupport::TestCase
  test "touching card updates board updated_at" do
    board = boards(:one)
    card = cards(:one)

    assert_changes -> { board.reload.updated_at } do
      card.touch
    end
  end
end
```

### Testing HTTP Caching

```ruby
# test/controllers/boards_controller_test.rb
require "test_helper"

class BoardsControllerCachingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
    @board = boards(:one)
  end

  test "returns 304 when board unchanged" do
    get board_url(@board)
    assert_response :success
    etag = response.headers["ETag"]

    get board_url(@board), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "returns 200 when board updated" do
    get board_url(@board)
    etag = response.headers["ETag"]

    @board.touch

    get board_url(@board), headers: { "If-None-Match" => etag }
    assert_response :success
  end
end
```

### Testing Cache Invalidation

```ruby
# test/models/board_test.rb
require "test_helper"

class BoardCacheInvalidationTest < ActiveSupport::TestCase
  test "statistics cache is cleared after card update" do
    board = boards(:one)
    card = cards(:one)

    board.statistics # Warm cache

    card.update!(title: "New title")

    assert_nil Rails.cache.read([board, "statistics"])
  end
end
```

## Memoization

```ruby
class EventPresenter < BasePresenter
  def vendor_count
    @vendor_count ||= event.vendors.count
  end
end
```

## Checklist

- [ ] Cache store configured for environment
- [ ] `fresh_when` on show/index actions
- [ ] `touch: true` on belongs_to for Russian doll
- [ ] Collection caching with `cached: true`
- [ ] Low-level caching for expensive queries
- [ ] Cache invalidation strategy defined
- [ ] Counter caches for counts
- [ ] Cache warming jobs for cold starts
- [ ] All tests GREEN
