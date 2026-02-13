---
plan: "01"
phase: 6
title: ssl-cert-store-configuration
status: COMPLETE
requirement: REQ-25
test_runs: 973
test_assertions: 3114
test_failures: 0
rubocop_offenses: 0
brakeman_warnings: 0
commits:
  - hash: c673d00
    message: "feat(06-01): add-ssl-settings-to-http-settings"
  - hash: f084129
    message: "feat(06-01): configure-faraday-ssl-cert-store"
  - hash: d2e3997
    message: "test(06-01): add-ssl-unit-tests"
  - hash: 6f0bbe8
    message: "test(06-01): record-netflix-vcr-cassette-and-regression-test"
deviations: none
---

## What Was Built

- **HTTPSettings SSL options** -- Added ssl_ca_file, ssl_ca_path, ssl_verify attr_accessors with safe defaults (verify=true, ca_file/ca_path=nil). Follows existing settings pattern.
- **Faraday SSL cert store** -- Every Faraday connection now gets an OpenSSL::X509::Store initialized with set_default_paths, loading all system-trusted CAs including intermediates. ssl_ca_file and ssl_ca_path override the store when set. General fix applying to ALL connections, not Netflix-specific.
- **SSL unit tests** -- 5 new tests covering default cert store, ca_file override, ca_path override, verify-true default, verify-false escape hatch. 13 total HTTP tests.
- **Netflix VCR cassette** -- Recorded from real Netflix Tech Blog feed (netflixtechblog.com/feed). Trimmed to 3 entries for manageable fixture size. Regression test parses as RSS and validates Netflix title and entries.

## Files Modified

- `lib/source_monitor/configuration/http_settings.rb` -- added ssl_ca_file, ssl_ca_path, ssl_verify settings
- `lib/source_monitor/http.rb` -- added require "openssl", configure_ssl method, default_cert_store method
- `test/lib/source_monitor/http_test.rb` -- 5 new SSL configuration tests
- `test/lib/source_monitor/fetching/feed_fetcher_test.rb` -- Netflix Tech Blog regression test
- `test/vcr_cassettes/source_monitor/fetching/netflix_medium_rss.yml` -- new VCR cassette
