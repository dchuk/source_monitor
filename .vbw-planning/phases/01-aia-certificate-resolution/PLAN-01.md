---
phase: 1
plan: 1
title: "AIA Resolver Module"
wave: 1
depends_on: []
must_haves:
  - AIAResolver module with resolve, enhanced_cert_store, clear_cache!, cache_size
  - Thread-safe Mutex + Hash cache with 1-hour TTL per hostname
  - fetch_leaf_certificate with VERIFY_NONE and SNI support
  - extract_aia_url using cert.ca_issuer_uris (not regex)
  - download_certificate with DER-first, PEM-fallback parsing
  - All methods rescue StandardError and return nil
  - Unit tests covering all public and private methods
---

# Plan 01: AIA Resolver Module

## Goal

Create `SourceMonitor::HTTP::AIAResolver` -- a standalone module that resolves missing intermediate certificates via the AIA (Authority Information Access) extension in X.509 certificates.

## Tasks

### Task 1: Create lib/source_monitor/http/aia_resolver.rb

Create new module `SourceMonitor::HTTP::AIAResolver` with class methods:

**Public API:**
- `resolve(hostname, port: 443)` -- Entry point. Checks cache first, then: fetch leaf cert -> extract AIA URL -> download intermediate. Returns `OpenSSL::X509::Certificate` or `nil`.
- `enhanced_cert_store(additional_certs)` -- Builds `OpenSSL::X509::Store` with `set_default_paths` plus extra certs from the array.
- `clear_cache!` -- Clears the hostname cache (for testing).
- `cache_size` -- Returns number of cached entries (for testing).

**Private methods:**
- `fetch_leaf_certificate(hostname, port)` -- TCP+SSL connect with `VERIFY_NONE` to get the server's leaf cert. 5s connect timeout. Uses `ssl_socket.hostname=` for SNI.
- `extract_aia_url(cert)` -- Uses Ruby's built-in `cert.ca_issuer_uris` method. Returns first URI string or nil.
- `download_certificate(url)` -- Plain HTTP GET (AIA URLs are always HTTP, not HTTPS). 5s timeout. Parses DER body as `OpenSSL::X509::Certificate`, falls back to PEM on failure.

**Cache:** `Mutex` + `Hash` keyed by hostname. Each entry stores `{ cert:, expires_at: }` with 1-hour TTL.

**Safety:** All methods rescue `StandardError` and return `nil`. This is best-effort -- never makes things worse.

### Task 2: Create test/lib/source_monitor/http/aia_resolver_test.rb

Unit tests:
- `extract_aia_url` with cert that has AIA extension returns URL
- `extract_aia_url` with cert without AIA returns nil
- `download_certificate` with DER body parses correctly (WebMock stub)
- `download_certificate` returns nil on HTTP 404 (WebMock)
- `download_certificate` returns nil on timeout (WebMock)
- `enhanced_cert_store` returns store with added certs
- `enhanced_cert_store` handles empty array gracefully
- Cache: resolve stores result, second call returns cached
- Cache: expired entries are re-fetched
- `clear_cache!` empties the cache
- `resolve` returns nil when hostname unreachable (stub fetch_leaf_certificate)

## Files

| Action | Path |
|--------|------|
| CREATE | `lib/source_monitor/http/aia_resolver.rb` |
| CREATE | `test/lib/source_monitor/http/aia_resolver_test.rb` |

## Verification

```bash
PARALLEL_WORKERS=1 bin/rails test test/lib/source_monitor/http/aia_resolver_test.rb
bin/rubocop lib/source_monitor/http/aia_resolver.rb test/lib/source_monitor/http/aia_resolver_test.rb
```
