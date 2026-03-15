---
phase: "03"
plan: "05"
title: "Import Step Handler Registry"
wave: 1
depends_on: []
must_haves:
  - "ImportSessionsController#update uses a STEP_HANDLERS constant or similar registry instead of 5 if/return branches"
  - "All 5 step handlers (upload, preview, health_check, configure, confirm) still work correctly"
  - "Invalid step name returns appropriate error (not a NoMethodError)"
  - "Existing import_sessions_controller_test.rb tests all pass without modification"
  - "bin/rails test passes, bin/rubocop zero offenses"
---

# Plan 05: Import Step Handler Registry

## Objective

Replace the repetitive string-matching dispatch in ImportSessionsController#update with a handler registry pattern (C5), improving maintainability without changing behavior.

## Context

- `app/controllers/source_monitor/import_sessions_controller.rb:42-47` dispatches via 5 sequential if/return branches
- Same pattern appears in `show` (lines 34-37) with `prepare_*_context` methods
- This is a pure refactoring -- no behavior change, no new files, no route changes
- The controller already includes 4 concerns that provide the step handler methods

## Tasks

### Task 1: Add step handler registry constant

Add to ImportSessionsController (near the top, after includes):

```ruby
STEP_HANDLERS = {
  "upload" => :handle_upload_step,
  "preview" => :handle_preview_step,
  "health_check" => :handle_health_check_step,
  "configure" => :handle_configure_step,
  "confirm" => :handle_confirm_step
}.freeze
```

### Task 2: Refactor update action

Replace the 5 if/return branches in `update` with:

```ruby
def update
  handler = STEP_HANDLERS[@current_step]
  return send(handler) if handler

  # fallback for unknown steps (existing behavior)
  @import_session.update!(session_attributes)
  @current_step = target_step
  @import_session.update_column(:current_step, @current_step) if @import_session.current_step != @current_step
  redirect_to source_monitor.step_import_session_path(@import_session, step: @current_step), allow_other_host: false
end
```

### Task 3: Refactor show action context preparation

Similarly, add a context preparation registry or simplify the show method:

```ruby
STEP_CONTEXTS = {
  "preview" => :prepare_preview_context,
  "health_check" => :prepare_health_check_context,
  "configure" => :prepare_configure_context,
  "confirm" => :prepare_confirm_context
}.freeze
```

Then in `show`:
```ruby
def show
  context_method = STEP_CONTEXTS[@current_step]
  send(context_method) if context_method
  persist_step!
  render :show
end
```

### Task 4: Verify

- `bin/rails test` -- all pass (especially import_sessions_controller_test.rb)
- `bin/rubocop` -- zero offenses
- Verify each step still works by tracing the handler dispatch
