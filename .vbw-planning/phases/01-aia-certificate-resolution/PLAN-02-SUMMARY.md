---
phase: 1
plan: 2
status: complete
commit: f60e9bf
---

## What Was Built
- Added `cert_store:` keyword parameter to `HTTP.client` for custom OpenSSL cert stores
- Added `autoload :AIAResolver` to HTTP module
- Plumbed cert_store through `configure_request` -> `configure_ssl` with fallback to `default_cert_store`
- 2 new tests: custom cert_store usage, ssl_ca_file takes precedence over cert_store

## Files Modified
- `lib/source_monitor/http.rb` — autoload, cert_store param, SSL plumbing
- `test/lib/source_monitor/http_test.rb` — 2 new cert_store tests
