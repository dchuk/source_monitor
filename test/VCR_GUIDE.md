# VCR Cassette Maintenance Guide

## Overview

VCR is configured in `test/test_helper.rb` and hooks into WebMock. Cassettes (recorded HTTP interactions) are stored as YAML files in `test/vcr_cassettes/`.

Configuration (from `test_helper.rb`):

```ruby
VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("vcr_cassettes", __dir__)
  config.hook_into :webmock
  config.ignore_localhost = true
end
```

## Naming Convention

Cassettes follow the pattern: `source_monitor/<domain>/<scenario>`

Examples:
- `source_monitor/fetching/rss_success`
- `source_monitor/fetching/atom_success`
- `source_monitor/fetching/json_success`

The domain groups cassettes by feature area. The scenario describes the specific interaction being recorded.

## When to Use VCR vs WebMock Stubs

**Use VCR when:**
- Testing complex multi-request flows where realistic response bodies matter
- Response content is parsed and validated (e.g., feed parsing, HTML scraping)
- You want to record a real interaction once and replay it deterministically

**Use WebMock stubs when:**
- Testing single-request behavior (status codes, timeouts, errors)
- Response content is irrelevant to the test (e.g., "returns 200")
- You need to simulate error conditions (timeouts, connection failures)
- The test needs fine-grained control over response headers or timing

## Recording New Cassettes

1. Write the test using `VCR.use_cassette`:

```ruby
test "fetches feed successfully" do
  source = create_source!(feed_url: "https://example.com/feed.xml")

  VCR.use_cassette("source_monitor/fetching/new_scenario", record: :new_episodes) do
    result = FeedFetcher.new(source: source, jitter: ->(_) { 0 }).call
    assert_equal :fetched, result.status
  end
end
```

2. Run the test. VCR will make the real HTTP request and save the response.
3. Review the generated YAML file in `test/vcr_cassettes/`.
4. Remove `record: :new_episodes` so future runs use the recorded cassette.
5. Commit the YAML cassette file alongside the test.

## Regenerating Stale Cassettes

When a cassette becomes outdated (upstream API changes, expired SSL certs, format changes):

1. Delete the stale YAML file from `test/vcr_cassettes/`.
2. Temporarily add `record: :new_episodes` to the `VCR.use_cassette` call.
3. Run the test to re-record the interaction.
4. Review the diff to ensure the new recording is valid.
5. Remove `record: :new_episodes` and commit the updated cassette.

## Current Cassettes

| Cassette | Purpose |
|----------|---------|
| `source_monitor/fetching/rss_success.yml` | Successful RSS feed fetch (ruby-lang.org news) |
| `source_monitor/fetching/atom_success.yml` | Successful Atom feed fetch |
| `source_monitor/fetching/json_success.yml` | Successful JSON feed fetch |
| `source_monitor/fetching/netflix_medium_rss.yml` | Medium-sized RSS feed (Netflix tech blog) |

## Maintenance

- **Review annually** or when upstream feed formats change.
- **SSL certificate expiry**: Cassettes with recorded SSL handshakes may fail when certs expire. Re-record the cassette to capture fresh cert chains.
- **Sensitive data**: Before committing, review cassettes for accidentally recorded API keys, tokens, or cookies. Use VCR's `filter_sensitive_data` if needed.
- **File size**: Keep cassettes reasonable. If a cassette exceeds 100KB, consider whether a WebMock stub would suffice.
