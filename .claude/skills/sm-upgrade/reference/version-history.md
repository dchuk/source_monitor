# Version-Specific Upgrade Notes

Version-specific migration notes for each major/minor version transition. Agents should reference this file when guiding users through multi-version upgrades.

## 0.3.x to 0.4.0

**Released:** 2026-02-12

**Key changes:**
- Install generator now auto-patches `Procfile.dev` and `queue.yml` dispatcher config
- New Active Storage image download feature (opt-in via `config.images.download_to_active_storage`)
- SSL certificate store configuration added to HTTPSettings
- RecurringScheduleVerifier and SolidQueueVerifier enhanced with better remediation messages
- Netflix Tech Blog VCR cassette regression test added

**Action items:**
1. Re-run `bin/rails source_monitor:upgrade` (or `bin/rails generate source_monitor:install`) to get Procfile.dev and queue.yml patches
2. If using Active Storage image downloads, add `config.images.download_to_active_storage = true` to initializer
3. If experiencing SSL certificate errors, new `config.http.ssl_ca_file`, `config.http.ssl_ca_path`, and `config.http.ssl_verify` settings are available
4. No breaking changes -- all existing configuration remains valid

## 0.2.x to 0.3.0

**Released:** 2026-02-10

**Key changes:**
- Major refactoring: FeedFetcher, Configuration, ImportSessionsController, ItemCreator all extracted into smaller modules
- Ruby autoload replaces eager requires in `lib/source_monitor.rb`
- LogEntry no longer uses hard-coded table name
- Skills system added (14 `sm-*` skills)
- Upgraded to Ruby 4.0.1 and Rails 8.1.2

**Action items:**
1. If you monkey-patched or referenced internal classes (FeedFetcher internals, Configuration nested classes), check that your references still resolve
2. Run `bin/rails source_monitor:upgrade` to copy any new migrations
3. Optionally install skills: `bin/rails source_monitor:skills:install`
4. No configuration changes required -- public API unchanged

## 0.1.x to 0.2.0

**Released:** 2025-11-25

**Key changes:**
- OPML import wizard added with multi-step flow
- ImportHistory model and migrations added
- Health check enqueuing and Turbo Stream updates during wizard

**Action items:**
1. Copy and run new migrations: `bin/rails railties:install:migrations FROM=source_monitor && bin/rails db:migrate`
2. No configuration changes required

## Future Versions

Template for documenting future upgrades:

```
## X.Y.Z to A.B.C
Released: YYYY-MM-DD

Key changes:
- ...

Action items:
1. ...

Deprecations:
- `old_option` replaced by `new_option` (warning in A.B.C, removal planned for D.E.F)
```
