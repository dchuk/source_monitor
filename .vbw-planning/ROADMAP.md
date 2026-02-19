# Roadmap

## Milestone: aia-ssl-fix

### Phases

1. [x] **AIA Certificate Resolution** -- Fix SSL failures for feeds with missing intermediate certificates by implementing AIA (Authority Information Access) resolution

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

### Progress

| Phase | Status | Plans | Completed |
|-------|--------|-------|-----------|
| 1. AIA Certificate Resolution | Planned | 3 | 0 |
