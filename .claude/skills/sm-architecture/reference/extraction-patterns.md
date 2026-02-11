# SourceMonitor Extraction Patterns

Patterns used during Phase 3 and Phase 4 refactoring to decompose large classes into focused sub-modules.

## Pattern 1: Sub-Module Extraction (FeedFetcher)

**Before:** `FeedFetcher` was 627 lines handling HTTP requests, response parsing, source state updates, adaptive interval calculation, and entry processing.

**After:** 285 lines in the main class + 3 sub-modules.

### Structure

```
lib/source_monitor/fetching/
  feed_fetcher.rb                    # 285 lines - orchestrator
  feed_fetcher/
    adaptive_interval.rb             # Interval calculation logic
    source_updater.rb                # Source state updates + fetch log creation
    entry_processor.rb               # Feed entry iteration + ItemCreator calls
```

### Technique

1. **Create sub-directory** matching the parent class name
2. **Extract cohesive responsibilities** into separate classes
3. **Pass dependencies via constructor** (source, adaptive_interval)
4. **Lazy accessor pattern** in parent:
   ```ruby
   def source_updater
     @source_updater ||= SourceUpdater.new(source: source, adaptive_interval: adaptive_interval)
   end
   ```
5. **Forwarding methods** for backward compatibility with tests:
   ```ruby
   def process_feed_entries(feed) = entry_processor.process_feed_entries(feed)
   def jitter_offset(interval_seconds) = adaptive_interval.jitter_offset(interval_seconds)
   ```
6. **Require in parent file** (not autoloaded -- explicit require):
   ```ruby
   require "source_monitor/fetching/feed_fetcher/adaptive_interval"
   require "source_monitor/fetching/feed_fetcher/source_updater"
   require "source_monitor/fetching/feed_fetcher/entry_processor"
   ```

### Key Design Decisions

- `AdaptiveInterval` is a pure calculator -- no side effects, receives source for reading config
- `SourceUpdater` handles all `source.update!` calls and fetch log creation
- `EntryProcessor` iterates entries and fires events (item_processors, after_item_created)
- Parent `FeedFetcher` remains the public API (`#call`) and coordinates the pipeline

---

## Pattern 2: Configuration Decomposition

**Before:** `Configuration` was 655 lines with all settings inline.

**After:** 87 lines composing 12 standalone settings objects.

### Structure

```
lib/source_monitor/configuration.rb          # 87 lines - composer
lib/source_monitor/configuration/
  http_settings.rb
  fetching_settings.rb
  health_settings.rb
  scraping_settings.rb
  realtime_settings.rb
  retention_settings.rb
  authentication_settings.rb
  scraper_registry.rb
  events.rb
  validation_definition.rb
  model_definition.rb
  models.rb
```

### Technique

1. **One settings class per domain** (HTTP, fetching, health, etc.)
2. **Composition via attr_reader** in parent:
   ```ruby
   attr_reader :http, :scrapers, :retention, :events, :models,
               :realtime, :fetching, :health, :authentication, :scraping
   ```
3. **Initialize all in constructor**:
   ```ruby
   def initialize
     @http = HTTPSettings.new
     @fetching = FetchingSettings.new
     # ...
   end
   ```
4. **Each settings class is a PORO** with `attr_accessor` and sensible defaults
5. **Explicit require** (not autoloaded) since Configuration is boot-critical

### Key Design Decisions

- Settings objects are simple POROs, not ActiveModel objects
- No validation at settings level -- validated at usage point
- Host app accesses via `config.http.timeout = 30` (dot-chain)
- Reset via `@config = Configuration.new` (new object, not clearing fields)

---

## Pattern 3: Controller Concern Extraction (ImportSessionsController)

**Before:** `ImportSessionsController` was 792 lines with wizard logic, health checks, and OPML parsing.

**After:** 295 lines + 4 concerns.

### Structure

```
app/controllers/source_monitor/import_sessions_controller.rb   # 295 lines
app/controllers/concerns/source_monitor/import_sessions/
  step_navigation.rb          # Wizard step logic
  health_checking.rb          # Health check actions
  source_selection.rb         # Source selection/deselection
  import_execution.rb         # Final import execution
```

### Technique

1. **Group by wizard step/feature** -- each concern handles a coherent set of actions
2. **Include in controller**:
   ```ruby
   include ImportSessions::StepNavigation
   include ImportSessions::HealthChecking
   ```
3. **Share state via controller methods** (e.g., `@import_session`, `current_user`)
4. **Before-action filters** stay in main controller for clarity

---

## Pattern 4: Processor Extraction (ItemCreator)

**Before:** `ItemCreator` was 601 lines handling entry parsing, content extraction, readability processing, and item persistence.

**After:** 174 lines + EntryParser (390 lines) + ContentExtractor (113 lines).

### Structure

```
lib/source_monitor/items/
  item_creator.rb                        # 174 lines - orchestrator
  item_creator/
    entry_parser.rb                      # 390 lines - parse feed entries
    entry_parser/media_extraction.rb     # Media parsing concern
    content_extractor.rb                 # 113 lines - readability processing
```

### Technique

1. **EntryParser** handles all Feedjira entry field extraction:
   - URL extraction, timestamp parsing, author normalization
   - GUID generation, fingerprint calculation
   - Category/tag/keyword parsing, media extraction
   - Includes `MediaExtraction` concern for media-specific parsing

2. **ContentExtractor** handles readability content processing:
   - Decision logic for when to process content
   - HTML wrapping for readability parser
   - Result metadata building

3. **Parent ItemCreator** remains the public API (`#call`, `.call`) and handles:
   - Duplicate detection (by GUID or fingerprint)
   - Create vs update decision
   - Concurrent duplicate handling (rescue RecordNotUnique)

4. **Forwarding methods** for backward compatibility (same as FeedFetcher pattern)

---

## Common Principles Across All Extractions

1. **Public API stays on the parent** -- callers don't need to change
2. **Backward-compatible forwarding** -- old test callsites keep working
3. **Constructor injection** -- dependencies passed in, not looked up globally
4. **Lazy accessors** -- sub-modules created on first use
5. **Explicit require** for sub-modules (not autoloaded) since parent requires them
6. **Cohesion over size** -- extract by responsibility, not arbitrary line count
7. **No inheritance** -- composition via delegation, not subclassing

## When to Apply

Use sub-module extraction when a class has:
- 3+ distinct responsibilities that can be named
- Methods that cluster into groups with different collaborators
- Test files that are hard to navigate due to mixed concerns
- A clear "orchestrator" role that coordinates the extracted pieces
