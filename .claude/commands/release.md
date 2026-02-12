# Release: PR, CI, Merge, and Gem Build

Orchestrate a full release cycle for the source_monitor gem. This command handles changelog generation, version bumping, PR creation, CI monitoring, auto-merge on success, release tagging, and gem build with push instructions.

## Inputs

- `$ARGUMENTS` -- Optional: version bump description or release notes summary. If empty, derive from commits since last tag.

## Known Gotchas (Read Before Starting)

These are real issues encountered in previous releases. Each step below accounts for them, but keep them in mind:

1. **Two version files**: Both `lib/source_monitor/version.rb` AND the top-level `VERSION` file must be bumped. The VBW pre-push hook checks for changes to `VERSION` (the top-level file).
2. **Gemfile.lock sync**: After bumping the version in `version.rb`, you MUST run `bundle install` to update `Gemfile.lock`. CI runs `bundle install --frozen` which fails if the lockfile is stale.
3. **VBW volatile files**: Files in `.vbw-planning/` (`.cost-ledger.json`, `.notification-log.jsonl`, `.session-log.jsonl`, `.hook-errors.log`) are continuously modified by VBW hooks. They should be in `.gitignore`. If they aren't, add them before proceeding.
4. **Pre-push hook**: The VBW pre-push hook at `.git/hooks/pre-push` requires the `VERSION` file to appear in the diff for any push. For new branches, it compares the commit against the working tree -- any dirty files will trigger a false positive. For force-pushes to existing branches where `VERSION` hasn't changed since the last push, use `--no-verify`.
5. **Single squashed commit**: Always create ONE commit on the release branch with ALL changes (version bump, changelog, Gemfile.lock, any fixes). Multiple commits cause pre-push hook issues.
6. **Diff coverage CI gate**: The `test` CI job enforces diff coverage. Any changed lines in source code (not just test files) must have test coverage. If you change source code during the release (e.g., bug fixes), you must add corresponding tests.
7. **Local main divergence after merge**: After the PR merges, local main will have different commits than origin/main (pre-squash vs merged). You must `git reset --hard origin/main` to sync -- this requires user approval since the sandbox blocks it.

## Step 1: Git Hygiene

Run these checks. If ANY fail, STOP and report the issue to the user.

1. **VBW volatile files gitignored**: Check that `.gitignore` contains these entries:
   ```
   .vbw-planning/.cost-ledger.json
   .vbw-planning/.notification-log.jsonl
   .vbw-planning/.session-log.jsonl
   .vbw-planning/.hook-errors.log
   ```
   If any are missing, add them. If any of these files are tracked by git, remove them from tracking with `git rm --cached <file>`.

2. **Working tree clean**: `git status --porcelain` must be empty (ignoring the VBW volatile files which should now be gitignored). If not, list the dirty files and ask the user whether to commit, stash, or abort.

3. **On main branch**: `git branch --show-current` must be `main`. If not, ask the user if they want to continue from the current branch or switch.

4. **Fetch latest**: `git fetch origin main`

5. **Up to date with remote**: Compare `git rev-parse HEAD` with `git rev-parse origin/main`. If behind, ask the user whether to pull.

6. **No unpushed commits**: Compare local HEAD with `origin/main`. If ahead, note how many commits are unpushed -- these will be included in the release.

Report a summary:
```
Git Status:
  Branch: main
  Clean: yes
  VBW files gitignored: yes
  Synced with origin: yes
  Unpushed commits: N
```

## Step 2: Version Check

1. Read `lib/source_monitor/version.rb` to get the current VERSION constant.
2. Read the top-level `VERSION` file to verify it matches. If they differ, sync them before proceeding.
3. Read the latest git tag with `git tag --sort=-v:refname | head -1`.
4. If the VERSION matches the latest tag (e.g., both are `0.3.2`), the version hasn't been bumped. Ask the user:
   - "Current version is X.Y.Z which already has a tag. What should the new version be?"
   - Offer options: patch (X.Y.Z+1), minor (X.Y+1.0), major (X+1.0.0), or custom.
   - Update BOTH `lib/source_monitor/version.rb` AND the top-level `VERSION` file with the new version.
5. If VERSION is ahead of the latest tag, proceed with the current version.

Store the release version for later steps. Do NOT commit yet -- that happens after the changelog is updated.

## Step 3: Update CHANGELOG.md

The changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. The file is at `CHANGELOG.md` in the project root.

1. **Gather commit history** since the last tag:
   ```
   git log vPREVIOUS..HEAD --oneline --no-merges
   ```
2. **Categorize commits** into Keep a Changelog sections based on commit prefixes and content:
   - `feat:`, `add:` --> **Added**
   - `fix:`, `bugfix:` --> **Fixed**
   - `chore:`, `refactor:`, `perf:` --> **Changed**
   - `docs:` --> **Documentation** (only include if substantive)
   - `BREAKING:` or `!:` --> **Breaking Changes** (at the top)
   - `remove:`, `deprecate:` --> **Removed**
   - Skip merge commits, version bumps, and CI-only changes.
   - If `$ARGUMENTS` was provided, use it to inform/supplement the categorization.

3. **Draft the changelog entry** and present it to the user for review:
   ```
   ## [X.Y.Z] - YYYY-MM-DD

   ### Added
   - <items>

   ### Fixed
   - <items>

   ### Changed
   - <items>
   ```
   Each bullet should be a concise, user-facing description (not a raw commit message). Consolidate related commits into single bullets where it makes sense.

4. **Ask the user to approve** the changelog entry. Offer to edit if they want changes.

5. **Write the entry** into `CHANGELOG.md`:
   - Replace the `## [Unreleased]` section contents with `- No unreleased changes yet.`
   - Insert the new versioned entry immediately after the `## [Unreleased]` block and before the previous release entry.
   - Preserve all existing entries below.

## Step 4: Sync Gemfile.lock

**CRITICAL**: After updating `version.rb`, the gemspec version changes and `Gemfile.lock` becomes stale.

1. Run `bundle install` to update `Gemfile.lock`.
2. Verify the output shows the new version: `Using source_monitor X.Y.Z (was X.Y.Z-1)`.
3. If `bundle install` fails, resolve the issue before proceeding.

## Step 5: Create Release Branch with Single Squashed Commit

**IMPORTANT**: All release changes MUST be in a single commit on the release branch. This avoids pre-push hook issues where individual commits are checked for VERSION changes.

1. Create the release branch from main: `git checkout -b release/vX.Y.Z`
2. Stage ALL release files in one commit:
   ```
   git add lib/source_monitor/version.rb VERSION CHANGELOG.md Gemfile.lock
   ```
   Also stage any other files that were changed (updated skills, docs, etc.).
3. Create a single commit:
   ```
   chore: release vX.Y.Z
   ```
4. Push the branch: `git push -u origin release/vX.Y.Z`
   - If the pre-push hook blocks with a false positive (e.g., VBW files dirty in working tree despite being gitignored), use `git push -u --no-verify origin release/vX.Y.Z`. This is safe because we've verified VERSION is in the commit.
5. If the push fails for other reasons, diagnose and fix before proceeding.

## Step 6: Create PR

1. Create the PR using `gh pr create`:
   - Title: `Release vX.Y.Z`
   - Body format:
     ```
     ## Release vX.Y.Z

     <paste the CHANGELOG.md entry content here>

     ### Release Checklist
     - [x] Version bumped in `lib/source_monitor/version.rb` and `VERSION`
     - [x] CHANGELOG.md updated
     - [x] Gemfile.lock synced
     - [ ] CI passes (lint, security, test, release_verification)

     ---
     Auto-generated release PR by `/release` command.
     ```
   - Base: `main`
2. Report the PR URL to the user.

## Step 7: Monitor CI Pipeline

Poll the CI status using repeated `gh pr checks <PR_NUMBER>` calls. The CI has 4 required jobs: `lint`, `security`, `test`, `release_verification` (release_verification only runs after test passes).

1. Tell the user: "Monitoring CI pipeline for PR #N... This typically takes 3-5 minutes."
2. Wait 30 seconds before first poll (give CI time to start).
3. Poll with `gh pr checks <PR_NUMBER>` every 60 seconds, up to 15 minutes.
4. After each poll, report progress if any jobs completed or failed.

### If CI PASSES (all checks green):

Continue to Step 8.

### If CI FAILS:

1. Get the failure details: `gh pr checks <PR_NUMBER>` to identify which jobs failed.
2. For each failed job, fetch the log summary. Note: logs are only available after the **entire run** completes (not just one job). If `gh run view <RUN_ID> --log-failed` says "still in progress", wait and retry:
   ```
   gh run view <RUN_ID> --log-failed | tail -80
   ```
3. **Common failure: diff coverage** -- If the `test` job fails on "Enforce diff coverage", it means changed source lines lack test coverage. Read the error to identify uncovered files/lines, write tests, and add them to the release commit.
4. **Common failure: Gemfile.lock frozen** -- If `bundle install` fails in CI with "frozen mode", you forgot to run `bundle install` locally (Step 4).
5. Present failure details to the user and ask what to do:
   - "Fix the issues and re-push" -- Fix issues, amend the commit (`git commit --amend --no-edit`), force push (`git push --force-with-lease --no-verify origin release/vX.Y.Z`), and restart CI monitoring.
   - "Close the PR and abort" -- Close the PR, delete the branch, switch back to main.
   - "Investigate manually" -- Stop and let the user handle it.

**Note on force pushes**: When force-pushing the release branch after amending, always use `--no-verify` because the pre-push hook will see the diff between old and new branch tips, and `VERSION` won't appear as changed (it's the same in both). This is expected and safe.

## Step 8: Auto-Merge PR

Once CI is green:

1. Merge the PR: `gh pr merge <PR_NUMBER> --merge --delete-branch`

2. **Sync local main with remote** (this is the tricky part):
   - The merge creates a merge commit on origin/main that doesn't exist locally.
   - Local main may have different commits (pre-squash) than what was merged.
   - Switch to main: `git checkout main`
   - Try `git pull origin main`. If it fails with conflicts or divergence:
     - Ask the user to run `git reset --hard origin/main` (the sandbox blocks this command).
     - Explain this is safe because the PR is merged and all changes are on origin/main.
   - Verify with `git log --oneline -3` that local matches remote.

3. Report: "PR #N merged successfully."

## Step 9: Tag the Release

1. Verify you're on main and synced with origin.
2. Create an annotated tag:
   ```
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   ```
3. Push the tag: `git push origin vX.Y.Z`
4. Create a GitHub release from the tag:
   ```
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "<changelog entry from Step 3>"
   ```
5. Report the release URL.

## Step 10: Build the Gem

1. Clean any old gem files: `ls source_monitor-*.gem` and remove them if found (don't error if none exist).
2. Build the gem: `gem build source_monitor.gemspec`
3. Verify the gem was built: check for `source_monitor-X.Y.Z.gem` in the project root.
4. Show the file size: `ls -la source_monitor-X.Y.Z.gem`

## Step 11: Gem Push Instructions

Present the final instructions to the user:

```
Release vX.Y.Z Complete!

  Git tag:    vX.Y.Z (pushed)
  GitHub:     <release URL>
  PR:         <PR URL> (merged)
  Gem built:  source_monitor-X.Y.Z.gem

To publish to RubyGems:

  gem push source_monitor-X.Y.Z.gem

You'll be prompted for your RubyGems OTP code (check your authenticator app).
The gem has `rubygems_mfa_required` enabled, so the OTP is mandatory.

After pushing, verify at:
  https://rubygems.org/gems/source_monitor/versions/X.Y.Z
```

Do NOT run `gem push` automatically -- always let the user handle the OTP-protected push manually.

## Error Recovery

- If any step fails unexpectedly, report what happened and where things stand.
- If a release branch already exists, ask the user whether to reuse or recreate it.
- If the tag already exists, skip tagging and inform the user.
- If the pre-push hook blocks, check whether `VERSION` (top-level) is in the commit diff. If it is and the hook still blocks (working tree drift from VBW), use `--no-verify`.
- If local main diverges from origin after merge, ask the user to run `git reset --hard origin/main`.
- Always leave the user on the `main` branch in a clean state when possible.
- If `gem build` warns about duplicate URIs (homepage_uri/source_code_uri), this is cosmetic and safe to ignore.
