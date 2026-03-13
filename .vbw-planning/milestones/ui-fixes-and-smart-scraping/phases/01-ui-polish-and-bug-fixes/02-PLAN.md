---
phase: "01"
plan: "02"
title: "SVG Favicon to PNG Conversion"
wave: 1
depends_on: []
must_haves:
  - "Detect SVG content type after favicon download"
  - "Convert SVG to PNG using MiniMagick before Active Storage attach"
  - "Graceful fallback if conversion fails"
  - "Tests for SVG conversion path"
---

## Tasks

### Task 1: Add mini_magick dependency

Add `mini_magick` gem to the gemspec as a runtime dependency (or development dependency if it should be optional).

**Files:**
- Modify: `source_monitor.gemspec` — add `spec.add_dependency "mini_magick"`

**Details:**
- MiniMagick is lightweight and widely used for image processing in Rails
- Requires ImageMagick installed on the host system
- Consider making it optional with a `defined?(MiniMagick)` guard

### Task 2: Add SVG-to-PNG conversion in favicon pipeline

After the Discoverer downloads a favicon, detect if it's SVG and convert to PNG before returning the Result.

**Files:**
- Modify: `lib/source_monitor/favicons/discoverer.rb` — add conversion step in `download_favicon` method
- Create: `lib/source_monitor/favicons/svg_converter.rb` — isolated conversion class
- Create: `test/lib/source_monitor/favicons/svg_converter_test.rb`

**Details:**
- In `download_favicon`, after validating content_type, check if `content_type == "image/svg+xml"`
- If SVG: pass the body through `SvgConverter.call(io)` which uses MiniMagick to convert to PNG
- SvgConverter returns a new Result with `content_type: "image/png"`, updated filename, and PNG io
- If conversion fails: log warning, return nil (skip this favicon, try next candidate)
- Keep `image/svg+xml` in `allowed_content_types` so SVGs are downloaded, but always convert before returning

### Task 3: Test SVG favicon flow end-to-end

Write tests covering the SVG detection and conversion path.

**Files:**
- Create: `test/lib/source_monitor/favicons/svg_converter_test.rb`
- Modify: `test/lib/source_monitor/favicons/discoverer_test.rb` — add SVG scenario

**Acceptance:**
- SVG favicon downloaded from a site is converted to PNG before attachment
- If MiniMagick/ImageMagick unavailable, fails gracefully (returns nil)
- Non-SVG favicons pass through unchanged
- Converted PNG has correct content_type and filename
