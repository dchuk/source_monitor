# SourceMonitor Release Checklist

## Automated Gates
- [ ] Confirm the `release_verification` GitHub Actions job succeeded on the target commit (generator smoke test, gem build/unpack, diff coverage).
- [ ] Ensure the standard CI jobs (`lint`, `security`, `test`) are green.

## Manual Validation
- [ ] Run `bin/release VERSION` locally and inspect the console output for any skipped steps or warnings.
- [ ] Inspect `pkg/source_monitor-<VERSION>.gem`:
  - [ ] Verify file size is within expected bounds compared to the previous release.
  - [ ] Extract the gem (`gem unpack`) and confirm `lib/` and templates are present.
- [ ] Review `CHANGELOG.md` entry for the release and ensure the annotated tag message matches.
- [ ] Preview the README locally with a Markdown renderer to confirm formatting.
- [ ] Confirm `config/coverage_baseline.json` is up to date (rerun `bin/test-coverage` + `bin/update-coverage-baseline` if functional coverage changed).
- [ ] Smoke test the disposable host app harness:
  - [ ] `bin/rails test test/integration/release_packaging_test.rb`
  - [ ] `bin/rails runner 'SourceMonitor::FetchFeedJob'` in the dummy app if new background job behavior shipped.
- [ ] Verify any new environment variables or configuration flags are documented in `docs/installation.md` or `docs/deployment.md`.

## Publication
- [ ] Tag the release (`git tag v<VERSION> -F <TAG_FILE>`) and push the tag.
- [ ] Publish the gem (`gem push pkg/source_monitor-<VERSION>.gem`).
- [ ] Announce the release (Slack/email) with highlights and migration notes.
