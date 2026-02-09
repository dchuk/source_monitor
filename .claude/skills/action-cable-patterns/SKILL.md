---
name: action-cable-patterns
description: Implements real-time features with Action Cable and WebSockets. Use when adding live updates, chat features, notifications, real-time dashboards, or when user mentions Action Cable, WebSockets, channels, or real-time.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Action Cable Patterns for Rails 8

## Overview

Action Cable integrates WebSockets with Rails:
- Real-time updates without polling
- Server-to-client push notifications
- Chat and messaging features
- Live dashboards and feeds

## Quick Start

```yaml
# config/cable.yml
development:
  adapter: async

test:
  adapter: test

production:
  adapter: solid_cable  # Rails 8 default
```

## Connection Authentication

```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      if session_token = cookies.signed[:session_token]
        if session = Session.find_by(token: session_token)
          session.user
        else
          reject_unauthorized_connection
        end
      else
        reject_unauthorized_connection
      end
    end
  end
end
```

## Channel Patterns

### Pattern 1: Notifications Channel

```ruby
# app/channels/notifications_channel.rb
class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end

  def self.notify(user, notification)
    broadcast_to(user, {
      type: "notification",
      id: notification.id,
      title: notification.title,
      body: notification.body
    })
  end
end
```

### Pattern 2: Resource Updates Channel

```ruby
# app/channels/events_channel.rb
class EventsChannel < ApplicationCable::Channel
  def subscribed
    @event = Event.find(params[:event_id])

    if authorized?
      stream_for @event
    else
      reject
    end
  end

  def self.broadcast_update(event)
    broadcast_to(event, {
      type: "update",
      html: ApplicationController.renderer.render(
        partial: "events/event", locals: { event: event }
      )
    })
  end

  private

  def authorized?
    EventPolicy.new(current_user, @event).show?
  end
end
```

### Pattern 3: Integration with Turbo Streams

```ruby
# app/models/comment.rb
class Comment < ApplicationRecord
  after_create_commit -> {
    broadcast_append_to(
      [event, "comments"],
      target: "comments",
      partial: "comments/comment"
    )
  }

  after_destroy_commit -> {
    broadcast_remove_to([event, "comments"])
  }
end
```

```erb
<%# app/views/events/show.html.erb %>
<%= turbo_stream_from @event, "comments" %>

<div id="comments">
  <%= render @event.comments %>
</div>
```

## Broadcasting from Services

```ruby
module Events
  class UpdateService
    def call(event, params)
      event.update!(params)
      EventsChannel.broadcast_update(event)
      DashboardChannel.broadcast_stats(event.account)
      success(event)
    end
  end
end
```

## Testing Channels

### Channel Test (Minitest)

```ruby
# test/channels/notifications_channel_test.rb
require "test_helper"

class NotificationsChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = users(:one)
    stub_connection(current_user: @user)
  end

  test "subscribes successfully" do
    subscribe
    assert subscription.confirmed?
  end

  test "streams for the current user" do
    subscribe
    assert_has_stream_for @user
  end

  test "broadcasts notification to user" do
    subscribe
    notification = notifications(:one)

    assert_broadcast_on(
      NotificationsChannel.broadcasting_for(@user),
      hash_including(type: "notification")
    ) do
      NotificationsChannel.notify(@user, notification)
    end
  end
end
```

### Channel with Authorization Test

```ruby
# test/channels/events_channel_test.rb
require "test_helper"

class EventsChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = users(:one)
    @event = events(:one) # belongs to @user's account
    @other_event = events(:other_account)
    stub_connection(current_user: @user)
  end

  test "subscribes to authorized event" do
    subscribe(event_id: @event.id)
    assert subscription.confirmed?
    assert_has_stream_for @event
  end

  test "rejects unauthorized event" do
    subscribe(event_id: @other_event.id)
    assert subscription.rejected?
  end
end
```

### Connection Test

```ruby
# test/channels/connection_test.rb
require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with valid session token" do
    user = users(:one)
    session = user.sessions.create!

    connect cookies: { session_token: session.token }

    assert_equal user, connection.current_user
  end

  test "rejects without session token" do
    assert_reject_connection do
      connect
    end
  end
end
```

## Stimulus Controller for Channels

```javascript
// app/javascript/controllers/chat_controller.js
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["messages", "input"]
  static values = { roomId: Number }

  connect() {
    this.channel = consumer.subscriptions.create(
      { channel: "ChatChannel", room_id: this.roomIdValue },
      {
        received: this.received.bind(this),
      }
    )
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  received(data) {
    if (data.type === "message") {
      this.messagesTarget.insertAdjacentHTML("beforeend", data.html)
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }
  }

  send(event) {
    event.preventDefault()
    const body = this.inputTarget.value.trim()
    if (body) {
      this.channel.perform("speak", { body })
      this.inputTarget.value = ""
    }
  }
}
```

## Checklist

- [ ] Connection authentication configured
- [ ] Channel authorization implemented
- [ ] Channel tests written
- [ ] Broadcasting from services/models
- [ ] Client-side subscription set up
- [ ] Turbo Stream integration (if applicable)
- [ ] All tests GREEN
