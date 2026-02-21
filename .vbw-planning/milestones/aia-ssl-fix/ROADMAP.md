# Roadmap

## Milestone: aia-ssl-fix

### Phases

1. [x] **AIA Certificate Resolution** -- Fix SSL failures for feeds with missing intermediate certificates by implementing AIA (Authority Information Access) resolution
2. [x] **Test Performance** -- Reduce test suite runtime from ~133s to ~50s by splitting monolithic test classes, enabling parallelism, reducing log IO, and adopting before_all

### Phase Details

#### Phase 1: AIA Certificate Resolution

**Goal:** Implement automatic AIA intermediate certificate fetching so feeds like netflixtechblog.com (served via Medium/AWS with wrong intermediates) succeed without manual cert configuration.

**Requirements:**
- REQ-AIA-01: Create AIAResolver module with thread-safe cache and 1-hour TTL
- REQ-AIA-02: Add cert_store: parameter to HTTP.client for custom cert stores
- REQ-AIA-03: On Faraday::SSLError, attempt AIA resolution before failing
- REQ-AIA-04: Best-effort only -- never make things worse (rescue StandardError -> nil)

**Success Criteria:**
- [ ] AIAResolver.resolve(hostname) fetches leaf cert, extracts AIA URL, downloads intermediate
- [ ] HTTP.client(cert_store:) accepts and uses custom cert stores
- [ ] FeedFetcher retries once with AIA-resolved cert store on SSL failure
- [ ] All existing tests pass (1003+), new tests cover AIA paths
- [ ] RuboCop zero offenses, Brakeman zero warnings

#### Phase 2: Test Performance

**Goal:** Reduce test suite wall-clock time from ~133s to ~50s through structural optimizations. The 3-agent investigation identified that FeedFetcherTest (71 tests, 84.8s, 64% of total) is a monolithic class that cannot be parallelized, integration tests add 31s, and 95MB of debug logging adds 5-15s.

**Requirements:**
- REQ-PERF-01: Split FeedFetcherTest into 5+ smaller classes by concern (success paths, error handling, adaptive interval, dirty-check, content fingerprint, utilities)
- REQ-PERF-02: Set test log level to :warn in test/dummy/config/environments/test.rb (eliminates 95MB log IO)
- REQ-PERF-03: Tag integration tests (host_install_flow, release_packaging) so they can be excluded during dev with --exclude-pattern
- REQ-PERF-04: Switch default parallelism from forks to threads (avoids PG segfault, enables splitting benefit)
- REQ-PERF-05: Adopt before_all/setup_once in top DB-heavy test files (dashboard/queries_test.rb, etc.)

**Success Criteria:**
- [ ] FeedFetcherTest split into 5+ files, each independently runnable
- [ ] All 1031+ tests pass with PARALLEL_WORKERS=1 and default workers
- [ ] Test suite completes in <70s locally (down from 133s)
- [ ] `bin/rails test --exclude-pattern="**/integration/**"` runs <50s
- [ ] RuboCop zero offenses, Brakeman zero warnings
- [ ] No test isolation regressions (parallel runs still green)

### Progress

| Phase | Status | Plans | Completed |
|-------|--------|-------|-----------|
| 1. AIA Certificate Resolution | Complete | 3 | 3 |
| 2. Test Performance | Complete | 4 | 4 |
