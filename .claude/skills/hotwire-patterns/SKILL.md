---
name: hotwire-patterns
description: Implements Hotwire patterns with Turbo Frames, Turbo Streams, and Stimulus controllers. Use when building interactive UIs, real-time updates, form handling, partial page updates, or when user mentions Turbo, Stimulus, or Hotwire.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Hotwire Patterns for Rails 8

## Overview

Hotwire = HTML Over The Wire. Build modern web apps without writing much JavaScript.

| Component | Purpose | Use Case |
|-----------|---------|----------|
| **Turbo Drive** | SPA-like navigation | Automatic, no code needed |
| **Turbo Frames** | Partial page updates | Inline editing, tabbed content |
| **Turbo Streams** | Real-time DOM updates | Live updates, flash messages |
| **Stimulus** | JavaScript sprinkles | Toggles, forms, interactions |

## When to Use Each Pattern

| Scenario | Pattern |
|----------|---------|
| Inline edit | Turbo Frame |
| Form submission with multiple updates | Turbo Stream |
| Real-time feed | Turbo Stream + ActionCable |
| Toggle visibility | Stimulus |
| Form validation | Stimulus |
| Infinite scroll | Turbo Frame + lazy loading |
| Modal dialogs | Turbo Frame |
| Flash messages | Turbo Stream |

## References

- See [turbo-frames.md](reference/turbo-frames.md) for frame patterns
- See [turbo-streams.md](reference/turbo-streams.md) for stream patterns
- See [stimulus.md](reference/stimulus.md) for controller patterns
- See [tailwind-integration.md](reference/tailwind-integration.md) for styling

## Turbo Frames

### Basic Frame

```erb
<%# app/views/posts/index.html.erb %>
<%= turbo_frame_tag "posts" do %>
  <%= render @posts %>
  <%= link_to "Load More", posts_path(page: 2) %>
<% end %>
```

### Inline Editing

```erb
<%# _post.html.erb %>
<%= turbo_frame_tag dom_id(post) do %>
  <article>
    <h2><%= post.title %></h2>
    <%= link_to "Edit", edit_post_path(post) %>
  </article>
<% end %>

<%# edit.html.erb %>
<%= turbo_frame_tag dom_id(@post) do %>
  <%= form_with model: @post do |f| %>
    <%= f.text_field :title %>
    <%= f.submit "Save" %>
    <%= link_to "Cancel", @post %>
  <% end %>
<% end %>
```

### Lazy Loading

```erb
<%= turbo_frame_tag "comments", src: post_comments_path(@post), loading: :lazy do %>
  <p>Loading comments...</p>
<% end %>
```

## Turbo Streams

### From Controller

```erb
<%# app/views/posts/create.turbo_stream.erb %>
<%= turbo_stream.prepend "posts", @post %>
<%= turbo_stream.update "flash", partial: "shared/flash" %>
```

### Stream Actions

```ruby
turbo_stream.append "posts", @post           # Add to end
turbo_stream.prepend "posts", @post          # Add to start
turbo_stream.replace dom_id(@post), @post    # Replace element
turbo_stream.update dom_id(@post), @post     # Replace inner HTML
turbo_stream.remove dom_id(@post)            # Remove element
```

### Flash Messages with Streams

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  after_action :flash_to_turbo_stream, if: -> { request.format.turbo_stream? }

  private

  def flash_to_turbo_stream
    flash.each do |type, message|
      flash.now[type] = message
    end
  end
end
```

## Stimulus Controllers

### Basic Controller

```javascript
// app/javascript/controllers/toggle_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]

  toggle() {
    this.contentTarget.classList.toggle("hidden")
  }
}
```

```erb
<div data-controller="toggle">
  <button data-action="toggle#toggle">Toggle</button>
  <div data-toggle-target="content">Hidden content</div>
</div>
```

### Form Controller

```javascript
// app/javascript/controllers/form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit"]

  enableSubmit() {
    this.submitTarget.disabled = false
  }

  disableSubmit() {
    this.submitTarget.disabled = true
  }
}
```

## Testing Hotwire

### Turbo Stream Response Tests

```ruby
# test/controllers/posts_controller_test.rb
require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "create returns turbo stream response" do
    post posts_path,
      params: { post: { title: "Test" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "turbo-stream"
  end

  test "create with HTML format redirects" do
    post posts_path, params: { post: { title: "Test" } }

    assert_redirected_to post_path(Post.last)
  end
end
```

### System Tests (with JavaScript)

```ruby
# test/system/posts_test.rb
require "application_system_test_case"

class PostsSystemTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "updates post inline with Turbo Frame" do
    post = posts(:one)

    visit posts_path
    within("#post_#{post.id}") do
      click_link "Edit"
      fill_in "Title", with: "Updated"
      click_button "Save"
    end

    assert_text "Updated"
    assert_no_text post.title
  end

  test "adds comment with Turbo Stream" do
    post = posts(:one)

    visit post_path(post)
    fill_in "Comment", with: "Great post!"
    click_button "Add Comment"

    within("#comments") do
      assert_text "Great post!"
    end
  end
end
```

## Debugging Tips

1. **Frame not updating?** Check frame IDs match exactly
2. **Stream not working?** Verify `Accept` header includes turbo-stream
3. **Stimulus not firing?** Check controller name matches file name
4. **Events not working?** Use `data-action="event->controller#method"`

## Checklist

- [ ] Identify update scope (full page vs partial)
- [ ] Choose pattern (Frame vs Stream vs Stimulus)
- [ ] Implement server response
- [ ] Add client-side markup
- [ ] Test with and without JavaScript
- [ ] Write system test for interactive behavior
- [ ] All tests GREEN
