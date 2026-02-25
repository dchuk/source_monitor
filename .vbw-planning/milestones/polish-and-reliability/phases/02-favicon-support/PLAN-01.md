---
phase: 2
plan: 1
title: "Favicon Infrastructure: Config, Model, Job, and Discovery"
wave: 1
depends_on: []
must_haves:
  - "FaviconsSettings class exists at lib/source_monitor/configuration/favicons_settings.rb with enabled, fetch_timeout, max_download_size, retry_cooldown_days, allowed_content_types attributes"
  - "SourceMonitor.config.favicons returns FaviconsSettings instance"
  - "Source model has has_one_attached :favicon guarded by if defined?(ActiveStorage)"
  - "FaviconFetchJob exists at app/jobs/source_monitor/favicon_fetch_job.rb with perform(source_id) and early return guards"
  - "Favicons::Discoverer exists at lib/source_monitor/favicons/discoverer.rb implementing multi-strategy cascade"
  - "Autoload declarations added to lib/source_monitor.rb for Favicons module"
  - "All new code has frozen_string_literal pragma"
  - "bin/rails test passes, bin/rubocop zero offenses"
skills_used: []
---

# Plan 01: Favicon Infrastructure: Config, Model, Job, and Discovery

## Objective

Build the complete backend infrastructure for favicon support: configuration settings, Source model attachment, favicon discovery logic, and the background job that orchestrates it all. REQ-FAV-01, REQ-FAV-02.

## Context

- `@lib/source_monitor/configuration/images_settings.rb` -- reference pattern for settings class (attr_accessors, reset!, constants)
- `@lib/source_monitor/configuration.rb` -- where to add `@favicons` instance and attr_reader (line 31, line 55)
- `@app/models/source_monitor/source.rb` -- add has_one_attached :favicon with guard (line 9 area, after includes)
- `@app/models/source_monitor/item_content.rb` -- proven ActiveStorage guard pattern: `has_many_attached :images if defined?(ActiveStorage)`
- `@app/jobs/source_monitor/download_content_images_job.rb` -- reference job pattern (find_by, early returns, blob create_and_upload!)
- `@lib/source_monitor/images/downloader.rb` -- reference for HTTP image download with validation
- `@lib/source_monitor.rb` -- autoload declarations (lines 90-93 for Images module)
- `@lib/source_monitor/http.rb` -- HTTP.client() for Faraday requests

## Tasks

### Task 1: Create FaviconsSettings configuration class

**Files:** `lib/source_monitor/configuration/favicons_settings.rb`

Create a new settings class following the ImagesSettings pattern:

```ruby
# frozen_string_literal: true

module SourceMonitor
  class Configuration
    class FaviconsSettings
      attr_accessor :enabled,
        :fetch_timeout,
        :max_download_size,
        :retry_cooldown_days,
        :allowed_content_types

      DEFAULT_FETCH_TIMEOUT = 5 # seconds
      DEFAULT_MAX_DOWNLOAD_SIZE = 1 * 1024 * 1024 # 1 MB
      DEFAULT_RETRY_COOLDOWN_DAYS = 7
      DEFAULT_ALLOWED_CONTENT_TYPES = %w[
        image/x-icon
        image/vnd.microsoft.icon
        image/png
        image/jpeg
        image/gif
        image/svg+xml
        image/webp
      ].freeze

      def initialize
        reset!
      end

      def reset!
        @enabled = true
        @fetch_timeout = DEFAULT_FETCH_TIMEOUT
        @max_download_size = DEFAULT_MAX_DOWNLOAD_SIZE
        @retry_cooldown_days = DEFAULT_RETRY_COOLDOWN_DAYS
        @allowed_content_types = DEFAULT_ALLOWED_CONTENT_TYPES.dup
      end

      def enabled?
        !!enabled && defined?(ActiveStorage)
      end
    end
  end
end
```

Then wire it into `lib/source_monitor/configuration.rb`:
1. Add `require "source_monitor/configuration/favicons_settings"` after the images_settings require (line 11)
2. Add `:favicons` to the `attr_reader` list (line 31)
3. In `initialize`, add `@favicons = FaviconsSettings.new` after `@images` (line 55)

**Tests:** `test/lib/source_monitor/configuration/favicons_settings_test.rb`
- Test defaults: enabled true, fetch_timeout 5, max_download_size 1MB, retry_cooldown_days 7, content types include image/x-icon
- Test reset! restores defaults after mutation
- Test enabled? returns false when @enabled is false
- Test enabled? returns true when ActiveStorage is defined and @enabled is true
- Test SourceMonitor.config.favicons returns FaviconsSettings instance

### Task 2: Add has_one_attached :favicon to Source model

**Files:** `app/models/source_monitor/source.rb`

Add the Active Storage attachment with the proven guard pattern. Insert after the existing includes (around line 9), before the FETCH_STATUS_VALUES constant:

```ruby
has_one_attached :favicon if defined?(ActiveStorage)
```

**Tests:** `test/models/source_monitor/source_favicon_test.rb`

Create a separate test file to avoid conflicts with the existing source_test.rb:
- Test that Source responds to :favicon when ActiveStorage is defined
- Test that a source can have a favicon attached (create blob, attach, verify attached?)
- Test that source creation works without favicon (no regression)

### Task 3: Create Favicons::Discoverer with multi-strategy cascade

**Files:** `lib/source_monitor/favicons/discoverer.rb`

Create the favicon discovery service that implements the cascade: /favicon.ico first, then HTML parsing, then Google Favicon API.

```ruby
# frozen_string_literal: true

module SourceMonitor
  module Favicons
    class Discoverer
      Result = Struct.new(:io, :filename, :content_type, :url, keyword_init: true)

      attr_reader :website_url, :settings

      def initialize(website_url, settings: nil)
        @website_url = website_url
        @settings = settings || SourceMonitor.config.favicons
      end

      def call
        return if website_url.blank?

        try_favicon_ico || try_html_link_tags || try_google_favicon_api
      rescue Faraday::Error, URI::InvalidURIError, Timeout::Error
        nil
      end

      private

      def try_favicon_ico
        # Build /favicon.ico URL from website_url
        uri = URI.parse(website_url)
        favicon_url = "#{uri.scheme}://#{uri.host}/favicon.ico"
        download_favicon(favicon_url)
      rescue URI::InvalidURIError
        nil
      end

      def try_html_link_tags
        # GET the HTML page, parse with Nokogiri for link[rel*=icon] and meta tags
        response = http_client.get(website_url)
        return unless response.status == 200

        doc = Nokogiri::HTML(response.body)
        candidates = extract_icon_candidates(doc)
        return if candidates.empty?

        # Try each candidate URL, prefer largest
        candidates.each do |candidate_url|
          result = download_favicon(candidate_url)
          return result if result
        end
        nil
      rescue Faraday::Error, Nokogiri::SyntaxError
        nil
      end

      def try_google_favicon_api
        # Google Favicon API: https://www.google.com/s2/favicons?domain=DOMAIN&sz=64
        uri = URI.parse(website_url)
        api_url = "https://www.google.com/s2/favicons?domain=#{uri.host}&sz=64"
        download_favicon(api_url)
      rescue URI::InvalidURIError
        nil
      end

      def extract_icon_candidates(doc)
        # ... parse link[rel] tags for icon types, meta tags for msapplication-TileImage
        # Return array of absolute URLs, sorted by preference (largest first)
        # Details in implementation
      end

      def download_favicon(url)
        # ... download, validate content type and size, return Result
      end

      def http_client
        # Build Faraday client with favicon-specific timeout
      end
    end
  end
end
```

Implementation details for `extract_icon_candidates`:
1. Search `link[rel]` tags where rel contains: icon, shortcut icon, apple-touch-icon, apple-touch-icon-precomposed, mask-icon
2. Use CSS selectors: `link[rel*="icon"]`, `link[rel="apple-touch-icon"]`, `link[rel="apple-touch-icon-precomposed"]`, `link[rel="mask-icon"]`
3. Search meta tags: `meta[name="msapplication-TileImage"]`, `meta[property="og:image"]` (as last resort)
4. Resolve relative URLs to absolute using URI.join with website_url
5. Sort candidates by `sizes` attribute if present (prefer larger: 256x256 > 32x32 > unsized)
6. Return array of absolute URL strings

Implementation details for `download_favicon`:
1. Use http_client to GET the URL with Accept: `image/*`
2. Validate response status == 200
3. Extract content_type from Content-Type header (split on ";", strip)
4. Validate content_type is in settings.allowed_content_types
5. Validate body size <= settings.max_download_size and > 0
6. Derive filename from URL path or generate one from content_type
7. Return Result struct with StringIO wrapping body

Implementation details for `http_client`:
1. Build Faraday connection with settings.fetch_timeout
2. Use SourceMonitor.config.http.user_agent for User-Agent header
3. Add Accept: `text/html, application/xhtml+xml` for HTML fetch, `image/*` for image download

**Tests:** `test/lib/source_monitor/favicons/discoverer_test.rb`

Use WebMock to stub HTTP responses:
- Test try_favicon_ico: stub /favicon.ico returning 200 with image/x-icon body, verify Result returned
- Test try_favicon_ico: stub 404, verify nil
- Test try_html_link_tags: stub HTML page with link[rel="icon"] tag, stub the linked image, verify Result
- Test try_html_link_tags: test with multiple icon candidates (prefer largest by sizes attribute)
- Test try_html_link_tags: test relative URL resolution (href="/icons/favicon.png")
- Test try_google_favicon_api: stub Google API returning PNG, verify Result
- Test cascade: /favicon.ico 404 -> HTML has icon -> returns HTML result
- Test cascade: all fail -> returns nil
- Test content type validation: rejects non-image MIME types
- Test max size validation: rejects oversized responses
- Test nil website_url: returns nil immediately
- Test network error handling: Faraday::Error returns nil

### Task 4: Create FaviconFetchJob

**Files:** `app/jobs/source_monitor/favicon_fetch_job.rb`

```ruby
# frozen_string_literal: true

module SourceMonitor
  class FaviconFetchJob < ApplicationJob
    source_monitor_queue :fetch

    discard_on ActiveJob::DeserializationError

    def perform(source_id)
      return unless defined?(ActiveStorage)

      source = SourceMonitor::Source.find_by(id: source_id)
      return unless source
      return unless SourceMonitor.config.favicons.enabled?
      return if source.website_url.blank?
      return if source.favicon.attached?
      return if within_cooldown?(source)

      result = SourceMonitor::Favicons::Discoverer.new(source.website_url).call

      if result
        attach_favicon(source, result)
      else
        record_failed_attempt(source)
      end
    rescue StandardError => error
      record_failed_attempt(source) if source
      log_error(source, error)
    end

    private

    def within_cooldown?(source)
      last_attempt = source.metadata&.dig("favicon_last_attempted_at")
      return false if last_attempt.blank?

      cooldown_days = SourceMonitor.config.favicons.retry_cooldown_days
      Time.parse(last_attempt) > cooldown_days.days.ago
    rescue ArgumentError, TypeError
      false
    end

    def attach_favicon(source, result)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: result.io,
        filename: result.filename,
        content_type: result.content_type
      )
      source.favicon.attach(blob)
    end

    def record_failed_attempt(source)
      metadata = (source.metadata || {}).merge(
        "favicon_last_attempted_at" => Time.current.iso8601
      )
      source.update_column(:metadata, metadata)
    rescue StandardError
      nil
    end

    def log_error(source, error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn(
        "[SourceMonitor::FaviconFetchJob] Failed for source #{source&.id}: #{error.class} - #{error.message}"
      )
    rescue StandardError
      nil
    end
  end
end
```

**Tests:** `test/jobs/source_monitor/favicon_fetch_job_test.rb`

- Test perform with valid source and website_url: stubs Discoverer to return result, asserts favicon.attached?
- Test perform with no ActiveStorage: returns early (skip if ActiveStorage always defined in test)
- Test perform with missing source_id: returns without error
- Test perform with blank website_url: returns without calling Discoverer
- Test perform with favicon already attached: returns without calling Discoverer
- Test perform within cooldown: set metadata["favicon_last_attempted_at"] to 1 day ago with 7-day cooldown, verify Discoverer not called
- Test perform outside cooldown: set metadata["favicon_last_attempted_at"] to 10 days ago, verify Discoverer called
- Test perform when Discoverer returns nil: records failed attempt in metadata
- Test perform with Discoverer error: rescues, records attempt, logs warning
- Test favicons disabled in config: returns early

### Task 5: Wire autoloads and require in source_monitor.rb

**Files:** `lib/source_monitor.rb`

Add the Favicons module autoload block after the Images module block (around line 93):

```ruby
module Favicons
  autoload :Discoverer, "source_monitor/favicons/discoverer"
end
```

Also add the require for the settings class in configuration.rb (already handled in Task 1).

Verify the full autoload chain works by running the test suite.

**Tests:** Verified via Task 1-4 tests running successfully. No separate test needed.

## Files

| Action | Path |
|--------|------|
| CREATE | `lib/source_monitor/configuration/favicons_settings.rb` |
| MODIFY | `lib/source_monitor/configuration.rb` |
| MODIFY | `app/models/source_monitor/source.rb` |
| CREATE | `lib/source_monitor/favicons/discoverer.rb` |
| CREATE | `app/jobs/source_monitor/favicon_fetch_job.rb` |
| MODIFY | `lib/source_monitor.rb` |
| CREATE | `test/lib/source_monitor/configuration/favicons_settings_test.rb` |
| CREATE | `test/models/source_monitor/source_favicon_test.rb` |
| CREATE | `test/lib/source_monitor/favicons/discoverer_test.rb` |
| CREATE | `test/jobs/source_monitor/favicon_fetch_job_test.rb` |

## Verification

```bash
bin/rails test test/lib/source_monitor/configuration/favicons_settings_test.rb test/models/source_monitor/source_favicon_test.rb test/lib/source_monitor/favicons/discoverer_test.rb test/jobs/source_monitor/favicon_fetch_job_test.rb
bin/rubocop lib/source_monitor/configuration/favicons_settings.rb lib/source_monitor/configuration.rb app/models/source_monitor/source.rb lib/source_monitor/favicons/discoverer.rb app/jobs/source_monitor/favicon_fetch_job.rb lib/source_monitor.rb
```

## Success Criteria

- FaviconsSettings accessible via SourceMonitor.config.favicons with correct defaults
- Source model has has_one_attached :favicon guarded by ActiveStorage check
- Discoverer implements /favicon.ico -> HTML parsing -> Google API cascade
- FaviconFetchJob handles all edge cases: missing source, no AS, cooldown, already attached
- Cooldown tracked in metadata JSONB (no schema migration needed)
- All new tests pass, zero RuboCop offenses
