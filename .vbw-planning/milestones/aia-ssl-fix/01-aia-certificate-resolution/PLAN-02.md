---
phase: 1
plan: 2
title: "HTTP Module cert_store Parameter"
wave: 1
depends_on: []
must_haves:
  - Add autoload :AIAResolver to module HTTP
  - Add cert_store keyword to client method
  - Pass cert_store through configure_request to configure_ssl
  - configure_ssl uses cert_store when no ssl_ca_file/ssl_ca_path
  - Tests for cert_store parameter usage
---

# Plan 02: HTTP Module cert_store Parameter

## Goal

Extend `SourceMonitor::HTTP.client` to accept an optional `cert_store:` parameter, enabling callers (like FeedFetcher's AIA retry) to provide a custom `OpenSSL::X509::Store` with additional certificates.

## Tasks

### Task 1: Modify lib/source_monitor/http.rb

1. Add autoload inside `module HTTP` (after RETRY_STATUSES):
   ```ruby
   autoload :AIAResolver, "source_monitor/http/aia_resolver"
   ```

2. Add `cert_store: nil` keyword to `client` method signature.

3. Pass `cert_store:` through `configure_request` to `configure_ssl`:
   - Add `cert_store:` parameter to `configure_request`
   - Pass it to `configure_ssl(connection, settings, cert_store:)`

4. In `configure_ssl`: when no `ssl_ca_file` or `ssl_ca_path` is set, use `cert_store || default_cert_store`.

### Task 2: Add tests to test/lib/source_monitor/http_test.rb

Add 2 tests:
- `cert_store: param is used when no ssl_ca_file or ssl_ca_path` -- pass a custom store, verify `connection.ssl.cert_store` is the custom store
- `cert_store: is ignored when ssl_ca_file is set` -- configure ssl_ca_file, pass cert_store, verify ca_file takes precedence

## Files

| Action | Path |
|--------|------|
| MODIFY | `lib/source_monitor/http.rb` |
| MODIFY | `test/lib/source_monitor/http_test.rb` |

## Verification

```bash
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/http_test.rb
bin/rubocop lib/source_monitor/http.rb test/lib/source_monitor/http_test.rb
```
