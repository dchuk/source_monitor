---
phase: 6
plan: "01"
title: ssl-cert-store-configuration
type: execute
wave: 1
depends_on: []
cross_phase_deps: []
autonomous: true
effort_override: thorough
skills_used: []
files_modified:
  - lib/source_monitor/configuration/http_settings.rb
  - lib/source_monitor/http.rb
  - test/lib/source_monitor/http_test.rb
  - test/lib/source_monitor/fetching/feed_fetcher_test.rb
  - test/vcr_cassettes/source_monitor/fetching/netflix_medium_rss.yml
must_haves:
  truths:
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/http_test.rb` exits 0 with 0 failures"
    - "Running `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb` exits 0 with 0 failures"
    - "Running `bin/rubocop lib/source_monitor/http.rb lib/source_monitor/configuration/http_settings.rb test/lib/source_monitor/http_test.rb test/lib/source_monitor/fetching/feed_fetcher_test.rb` exits 0 with no offenses"
    - "Running `bin/rails test` (full suite) exits 0 with 0 failures"
    - "`grep -r 'cert_store' lib/source_monitor/http.rb` returns at least one match"
    - "`grep -r 'ssl_ca_file' lib/source_monitor/configuration/http_settings.rb` returns at least one match"
    - "The VCR cassette at test/vcr_cassettes/source_monitor/fetching/netflix_medium_rss.yml exists and contains 'netflixtechblog'"
  artifacts:
    - path: "lib/source_monitor/http.rb"
      provides: "SSL cert store configuration on Faraday connections"
      contains: "cert_store"
    - path: "lib/source_monitor/configuration/http_settings.rb"
      provides: "Configurable SSL options (ca_file, ca_path, verify)"
      contains: "ssl_ca_file"
    - path: "test/lib/source_monitor/http_test.rb"
      provides: "Tests for SSL configuration on HTTP client"
      contains: "ssl"
    - path: "test/lib/source_monitor/fetching/feed_fetcher_test.rb"
      provides: "Netflix Tech Blog VCR regression test"
      contains: "netflix"
    - path: "test/vcr_cassettes/source_monitor/fetching/netflix_medium_rss.yml"
      provides: "Recorded VCR cassette from real Netflix Tech Blog feed"
      contains: "netflixtechblog"
  key_links:
    - from: "http.rb#configure_ssl"
      to: "REQ-25"
      via: "Configures Faraday SSL with system cert store to fix certificate verification failures"
    - from: "http_settings.rb#ssl_ca_file"
      to: "REQ-25"
      via: "Exposes configurable SSL CA file/path for environments with non-standard cert locations"
    - from: "feed_fetcher_test.rb#netflix_regression"
      to: "REQ-25"
      via: "VCR cassette proves Netflix Tech Blog feed parses successfully"
---
<objective>
Fix SSL certificate verification failures (like Netflix Tech Blog's "unable to get local issuer certificate") by configuring the Faraday HTTP client to use a properly initialized OpenSSL cert store with system default paths. Add configurable SSL options to HTTPSettings so users can override CA file/path in non-standard environments. Record a VCR cassette from the real Netflix Tech Blog feed as a regression test. REQ-25.
</objective>
<context>
@lib/source_monitor/http.rb -- The HTTP client module. Creates Faraday connections via `HTTP.client`. Currently configures timeouts, retry, gzip, follow-redirects, and headers -- but does NOT configure any SSL options. Faraday's `connection.ssl` is left at defaults, which means it relies on the underlying adapter (net_http) to find CA certs. On some systems (macOS with Homebrew Ruby, Docker Alpine, custom OpenSSL builds), the compiled-in `OpenSSL::X509::DEFAULT_CERT_FILE` path may not include all intermediate certificates -- causing "certificate verify failed" for sites like Netflix Tech Blog whose chain depends on intermediates served by the TLS handshake being validated against a complete CA bundle. The fix is to explicitly set `connection.ssl.cert_store` to an `OpenSSL::X509::Store` initialized with `set_default_paths`, which loads both `DEFAULT_CERT_FILE` and `DEFAULT_CERT_DIR`. Optionally, if the user configures `ssl_ca_file` or `ssl_ca_path`, those override the default store.

@lib/source_monitor/configuration/http_settings.rb -- The settings class for HTTP configuration. Has 11 `attr_accessor` fields for timeout, retry, proxy, headers, etc. New SSL settings (`ssl_ca_file`, `ssl_ca_path`, `ssl_verify`) should be added here following the same pattern. Default: `ssl_verify = true` (never disable verification), `ssl_ca_file = nil`, `ssl_ca_path = nil` (nil means use system defaults via cert_store).

@test/lib/source_monitor/http_test.rb -- 8 existing tests for the HTTP client. Tests inspect `@connection.builder.handlers`, `@connection.options`, and `@connection.headers`. New SSL tests should inspect `@connection.ssl.cert_store`, `@connection.ssl.verify`, and optionally `@connection.ssl.ca_file` when configured.

@test/lib/source_monitor/fetching/feed_fetcher_test.rb -- Existing tests use VCR cassettes for RSS, Atom, and JSON feeds (ruby-lang.org, W3C, json_sample). The Netflix regression test should follow the same pattern: `VCR.use_cassette("source_monitor/fetching/netflix_medium_rss")` with a source pointing at `https://netflixtechblog.com/feed`.

@test/vcr_cassettes/ -- Contains 3 existing cassettes (rss_success, atom_success, json_success). The Netflix cassette should be recorded with `VCR.use_cassette(..., record: :new_episodes)` during the first test run against the real feed (with WebMock allowing the Netflix host temporarily), then committed as a fixture for CI. This requires temporarily allowing net connect to netflixtechblog.com during recording.

@lib/source_monitor/fetching/feed_fetcher.rb -- Lines 84-85 already catch `Faraday::SSLError` and wrap it as `ConnectionError`. This error path will stop triggering once SSL is properly configured, but the error handling remains as a safety net for genuinely invalid certificates.

**Root cause analysis:**
The Netflix Tech Blog (Medium-hosted at netflixtechblog.com, IP 52.1.173.203) serves a TLS certificate chain that requires the client to have Amazon's intermediate CA in its trust store. Ruby's compiled-in `OpenSSL::X509::DEFAULT_CERT_FILE` may point to a cert bundle that is missing this intermediate, or the system's cert directory may not be indexed. By explicitly creating an `OpenSSL::X509::Store` with `set_default_paths` and assigning it to the Faraday connection's `ssl.cert_store`, we ensure Ruby loads all available system certificates -- which on a properly maintained system includes Amazon/AWS intermediates. This is the standard, general fix for SSL verification issues in Ruby HTTP clients.

**Key design decisions:**
1. Use `OpenSSL::X509::Store.new.tap(&:set_default_paths)` as the default cert store -- this is the most cross-platform approach
2. Add `ssl_ca_file` and `ssl_ca_path` as optional overrides in HTTPSettings -- when set, they configure `connection.ssl.ca_file` / `connection.ssl.ca_path` instead of using the cert store
3. Keep `ssl_verify = true` as default and do NOT add a way to disable verification globally -- security-first design
4. The cert store is created fresh per `HTTP.client` call (Faraday connections are short-lived and not shared across threads)
5. For recording the VCR cassette: use a dedicated recording script or a test with `record: :new_episodes` and temporarily permit net connect
</context>
<tasks>
<task type="auto">
  <name>add-ssl-settings-to-http-settings</name>
  <files>
    lib/source_monitor/configuration/http_settings.rb
  </files>
  <action>
Add three new `attr_accessor` fields to `HTTPSettings` for SSL configuration:

1. `ssl_ca_file` -- Path to a CA certificate file (PEM format). When set, Faraday uses this instead of the default cert store. Default: `nil`.
2. `ssl_ca_path` -- Path to a directory of CA certificates. When set, Faraday uses this. Default: `nil`.
3. `ssl_verify` -- Whether to verify SSL certificates. Default: `true`. This exists for completeness but should almost never be set to `false`.

Add the three new fields to the `attr_accessor` list (after `retry_statuses`):

```ruby
attr_accessor :timeout,
  :open_timeout,
  :max_redirects,
  :user_agent,
  :proxy,
  :headers,
  :retry_max,
  :retry_interval,
  :retry_interval_randomness,
  :retry_backoff_factor,
  :retry_statuses,
  :ssl_ca_file,
  :ssl_ca_path,
  :ssl_verify
```

In `reset!`, add after `@retry_statuses = nil`:

```ruby
@ssl_ca_file = nil
@ssl_ca_path = nil
@ssl_verify = true
```
  </action>
  <verify>
Read `lib/source_monitor/configuration/http_settings.rb` and confirm: (a) all three new attr_accessors are present, (b) `reset!` initializes them with correct defaults, (c) `ssl_verify` defaults to `true`.
  </verify>
  <done>
HTTPSettings now has ssl_ca_file, ssl_ca_path, and ssl_verify configuration options with safe defaults.
  </done>
</task>
<task type="auto">
  <name>configure-faraday-ssl-cert-store</name>
  <files>
    lib/source_monitor/http.rb
  </files>
  <action>
Modify the `HTTP` module to configure SSL on every Faraday connection. Add a `require "openssl"` at the top of the file (after the existing requires).

In the `configure_request` method, add SSL configuration BEFORE the adapter line (`connection.adapter Faraday.default_adapter`):

```ruby
configure_ssl(connection, settings)
```

Add a new private method `configure_ssl`:

```ruby
def configure_ssl(connection, settings)
  connection.ssl.verify = settings.ssl_verify != false

  if settings.ssl_ca_file
    connection.ssl.ca_file = settings.ssl_ca_file
  elsif settings.ssl_ca_path
    connection.ssl.ca_path = settings.ssl_ca_path
  else
    connection.ssl.cert_store = default_cert_store
  end
end

def default_cert_store
  OpenSSL::X509::Store.new.tap(&:set_default_paths)
end
```

The logic:
1. Always set `verify = true` unless explicitly configured to `false` (defense in depth).
2. If user specifies `ssl_ca_file`, use that (overrides cert store).
3. Else if user specifies `ssl_ca_path`, use that (overrides cert store).
4. Otherwise, create a fresh `OpenSSL::X509::Store` with `set_default_paths` -- this is the key fix that resolves the Netflix SSL error by loading all system CA certificates including intermediates.

Note: `ca_file` and `ca_path` take precedence over `cert_store` in Faraday/net_http, so we only set one path.
  </action>
  <verify>
Read `lib/source_monitor/http.rb` and confirm: (a) `require "openssl"` is present, (b) `configure_ssl` is called in `configure_request`, (c) the method creates an `OpenSSL::X509::Store` with `set_default_paths` as the default, (d) `ssl_ca_file` and `ssl_ca_path` override the store when set, (e) `ssl.verify` is always explicitly set. Run `bin/rubocop lib/source_monitor/http.rb` to confirm no offenses.
  </verify>
  <done>
The HTTP client now explicitly configures SSL with a proper cert store. By default, every Faraday connection gets an OpenSSL::X509::Store initialized with system default paths, which resolves certificate chain verification failures like the Netflix Tech Blog issue.
  </done>
</task>
<task type="auto">
  <name>add-ssl-unit-tests</name>
  <files>
    test/lib/source_monitor/http_test.rb
  </files>
  <action>
Add the following tests to `HTTPTest`:

1. **"configures SSL with default cert store"** -- Create a default client, assert `@connection.ssl.verify` is truthy, assert `@connection.ssl.cert_store` is an instance of `OpenSSL::X509::Store`, assert `@connection.ssl.ca_file` is nil (not overridden).

2. **"uses configured ssl_ca_file when set"** -- Configure `config.http.ssl_ca_file = "/path/to/custom/ca.pem"`, create a client, assert `connection.ssl.ca_file` equals the configured path, assert `connection.ssl.cert_store` is nil (ca_file takes precedence).

3. **"uses configured ssl_ca_path when set"** -- Configure `config.http.ssl_ca_path = "/path/to/certs"`, create a client, assert `connection.ssl.ca_path` equals the configured path.

4. **"ssl verify defaults to true"** -- Create a default client, assert `connection.ssl.verify` is `true`.

5. **"respects ssl_verify configuration"** -- Configure `config.http.ssl_verify = false`, create a client, assert `connection.ssl.verify` is `false`. (This tests the escape hatch exists, even though it should rarely be used.)

Add `require "openssl"` at the top of the test file if not already present.

Each test should follow the existing pattern: create a connection via `SourceMonitor::HTTP.client`, then inspect the `connection.ssl` object.
  </action>
  <verify>
Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/http_test.rb` and confirm all tests pass (8 existing + 5 new = 13 tests). Run `bin/rubocop test/lib/source_monitor/http_test.rb` and confirm no offenses.
  </verify>
  <done>
5 new SSL configuration tests added. All 13 HTTP client tests pass. The cert store, ca_file, ca_path, and verify options are all verified.
  </done>
</task>
<task type="auto">
  <name>record-netflix-vcr-cassette-and-regression-test</name>
  <files>
    test/lib/source_monitor/fetching/feed_fetcher_test.rb
    test/vcr_cassettes/source_monitor/fetching/netflix_medium_rss.yml
  </files>
  <action>
This task records a VCR cassette from the real Netflix Tech Blog feed and adds a regression test.

**Step 1: Record the VCR cassette.**

Create a temporary recording script or use a one-off test run. The simplest approach: add the test first (below), then run it once with `VCR_RECORD=new_episodes` or equivalent to record the cassette. The cassette will be committed as a test fixture.

To record, temporarily allow net connect for the Netflix host. You can do this by running:

```bash
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb -n test_fetches_netflix_tech_blog_feed_via_medium_rss
```

with VCR configured to `record: :new_episodes` for this specific cassette. If WebMock blocks the request, temporarily use `WebMock.allow_net_connect!` inside the test during recording, then remove it after the cassette is committed.

**Alternative recording approach:** Use a standalone Ruby script to fetch the feed and manually create the VCR cassette YAML:

```ruby
require "faraday"
require "openssl"
require "yaml"

conn = Faraday.new do |f|
  f.ssl.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
  f.request :gzip
  f.response :follow_redirects, limit: 5
  f.adapter :net_http
end

response = conn.get("https://netflixtechblog.com/feed")
# Save as VCR cassette format...
```

After recording, verify the cassette file exists at `test/vcr_cassettes/source_monitor/fetching/netflix_medium_rss.yml` and contains a 200 response with RSS/XML body containing Netflix blog entries.

**Step 2: Add the regression test.**

Add a new test to `FeedFetcherTest`:

```ruby
test "fetches Netflix Tech Blog feed via Medium RSS" do
  source = build_source(
    name: "Netflix Tech Blog",
    feed_url: "https://netflixtechblog.com/feed"
  )

  result = nil
  VCR.use_cassette("source_monitor/fetching/netflix_medium_rss") do
    result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
  end

  assert_equal :fetched, result.status
  assert_not_nil result.feed
  assert_kind_of Feedjira::Parser::RSS, result.feed
  assert result.feed.entries.any?, "Expected at least one feed entry"
  assert_match(/netflix/i, result.feed.title.to_s)
end
```

This test uses the recorded VCR cassette so it works in CI without network access. It validates that the feed parses as RSS and contains Netflix entries.

**Important:** The `build_source` helper is already available in this test file. Check existing test patterns to confirm the helper signature.
  </action>
  <verify>
Confirm: (a) the VCR cassette file exists at `test/vcr_cassettes/source_monitor/fetching/netflix_medium_rss.yml`, (b) it contains `netflixtechblog` in the request URI, (c) the response status is 200, (d) the response body contains RSS/XML content. Run `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb -n test_fetches_Netflix_Tech_Blog_feed_via_Medium_RSS` and confirm it passes.
  </verify>
  <done>
VCR cassette recorded from real Netflix Tech Blog feed. Regression test passes using the cassette. The feed parses as RSS with Netflix blog entries, proving the SSL fix resolves the original "certificate verify failed" error.
  </done>
</task>
<task type="auto">
  <name>full-suite-verification-and-documentation</name>
  <files>
    lib/source_monitor/http.rb
    lib/source_monitor/configuration/http_settings.rb
    test/lib/source_monitor/http_test.rb
    test/lib/source_monitor/fetching/feed_fetcher_test.rb
  </files>
  <action>
Run the full verification suite:

1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/http_test.rb test/lib/source_monitor/fetching/feed_fetcher_test.rb` -- all targeted tests pass
2. `bin/rails test` -- full suite passes with 874+ runs and 0 failures
3. `bin/rubocop` -- zero offenses
4. `bin/brakeman --no-pager` -- zero warnings

Review all modified files for:
- `http.rb`: `require "openssl"` present, `configure_ssl` called in `configure_request`, `default_cert_store` creates `OpenSSL::X509::Store` with `set_default_paths`
- `http_settings.rb`: three new attr_accessors (`ssl_ca_file`, `ssl_ca_path`, `ssl_verify`), initialized in `reset!`
- `http_test.rb`: 5 new SSL tests covering cert_store default, ca_file override, ca_path override, verify default, verify override
- `feed_fetcher_test.rb`: Netflix regression test using VCR cassette
- VCR cassette: valid YAML with Netflix feed content

If any failures or offenses are found, fix them before completing.

Add a brief inline comment in `http.rb` above `configure_ssl` documenting the root cause:

```ruby
# Configure SSL to use a proper cert store. Without this, some systems
# fail to verify certificate chains that depend on intermediate CAs
# (e.g., Medium/Netflix on AWS). OpenSSL::X509::Store#set_default_paths
# loads all system-trusted CAs including intermediates.
```
  </action>
  <verify>
`bin/rails test` exits 0 with 874+ runs, 0 failures. `bin/rubocop` exits 0 with 0 offenses. `bin/brakeman --no-pager` exits 0 with 0 warnings. All modified files are clean and well-documented.
  </verify>
  <done>
Full suite passes. All quality gates green. SSL cert store fix is general (not Netflix-specific), configurable via HTTPSettings, documented inline, and regression-tested with a VCR cassette.
  </done>
</task>
</tasks>
<verification>
1. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/http_test.rb` -- 13+ tests pass (8 existing + 5 new SSL tests)
2. `PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/fetching/feed_fetcher_test.rb` -- all tests pass including Netflix regression
3. `bin/rails test` -- 874+ runs, 0 failures
4. `bin/rubocop` -- 0 offenses
5. `bin/brakeman --no-pager` -- 0 warnings
6. `grep -n 'cert_store' lib/source_monitor/http.rb` returns matches for configure_ssl and default_cert_store
7. `grep -n 'ssl_ca_file' lib/source_monitor/configuration/http_settings.rb` returns match in attr_accessor and reset!
8. `test -f test/vcr_cassettes/source_monitor/fetching/netflix_medium_rss.yml` exits 0
9. `grep 'netflixtechblog' test/vcr_cassettes/source_monitor/fetching/netflix_medium_rss.yml` returns matches
</verification>
<success_criteria>
- Root cause identified: missing intermediate CA certs when OpenSSL cert store not explicitly initialized (REQ-25)
- General fix applied: Faraday SSL configured with OpenSSL::X509::Store#set_default_paths on every connection (REQ-25)
- Configurable: ssl_ca_file, ssl_ca_path, ssl_verify exposed via HTTPSettings for non-standard environments (REQ-25)
- Netflix Tech Blog feed fetches successfully via VCR cassette regression test (REQ-25)
- No regressions: existing SSL error wrapping (Faraday::SSLError -> ConnectionError) still works (REQ-25)
- VCR cassette recorded from real Netflix feed and committed as test fixture (REQ-25)
- All tests pass, RuboCop clean, Brakeman clean (REQ-25)
</success_criteria>
<output>
.vbw-planning/phases/06-netflix-feed-fix/PLAN-01-SUMMARY.md
</output>
