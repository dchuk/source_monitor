# Phase 2: Favicon Support — Context

Gathered: 2026-02-20
Calibration: architect

## Phase Boundary
Automatically fetch and store source favicons using Active Storage, displayed in the UI next to source names.

## Decisions

### Favicon Discovery Strategy
- Multi-strategy cascade in this order: /favicon.ico first → full HTML page GET with Nokogiri parsing → Google Favicon API as last resort
- DuckDuckGo API skipped (two external APIs is overkill)
- HTML parsing: search `<link>` tags for icon, shortcut icon, apple-touch-icon, apple-touch-icon-precomposed, mask-icon
- Also check `<meta>` tags for msapplication-TileImage and tile logos
- When multiple candidates found, prefer the largest available icon
- Reference implementation: https://github.com/AlexMili/extract_favicon (Python) — adapt key patterns to Ruby using Nokogiri, ImageProcessing/vips, and SourceMonitor::HTTP

### Image Processing & Variants
- Store raw original via Active Storage (preserve source fidelity)
- Define two Active Storage variants: 32x32 (standard) and 64x64 (retina)
- SVG favicons: store SVG as-is AND rasterize to PNG for variants
- Ruby stack: ImageProcessing gem with vips backend

### Refresh & Failure Policy
- Trigger: piggyback on successful feed fetches — if favicon is missing, enqueue FaviconFetchJob
- Also trigger on source creation
- On failure (all strategies exhausted): cooldown then retry
- Cooldown period: configurable via `config.favicons.retry_cooldown_days`, default 7 days
- Track last attempt timestamp to enforce cooldown

### Active Storage Optionality
- Active Storage is required for favicon feature (no URL-only fallback path)
- Source model uses `if defined?(ActiveStorage)` guard on `has_one_attached :favicon` (prevents crashes in host apps without AS)
- FaviconFetchJob includes early return guard: `return unless defined?(ActiveStorage)` (belt-and-suspenders)
- No Active Storage = no favicons, no errors

### Open (Claude's discretion)
- Favicon content type validation (only accept image/* MIME types)
- Max file size limit for downloaded favicons (e.g., 1MB cap)
- ICO file handling: parse ICO header to identify largest embedded sub-image (per extract_favicon pattern)
- Google Favicon API URL format and size parameter

## Deferred Ideas
None captured during discussion.
