# Release: PR, CI, Merge, and Gem Build

Orchestrate a full release cycle for the source_monitor gem. This command handles changelog generation, version bumping, PR creation, CI monitoring, auto-merge on success, release tagging, and gem build with push instructions.

## Inputs

- `$ARGUMENTS` -- Optional: version bump description or release notes summary. If empty, derive from commits since last tag.

## Step 1: Git Hygiene

Run these checks. If ANY fail, STOP and report the issue to the user.

1. **Working tree clean**: `git status --porcelain` must be empty. If not, list the dirty files and ask the user whether to commit, stash, or abort.
2. **On main branch**: `git branch --show-current` must be `main`. If not, ask the user if they want to continue from the current branch or switch.
3. **Fetch latest**: `git fetch origin main`
4. **Up to date with remote**: Compare `git rev-parse HEAD` with `git rev-parse origin/main`. If behind, ask the user whether to pull.
5. **No unpushed commits**: Compare local HEAD with `origin/main`. If ahead, note how many commits are unpushed -- these will be included in the PR.

Report a summary:
```
Git Status:
  Branch: main
  Clean: yes
  Synced with origin: yes
  Unpushed commits: N
```

## Step 2: Version Check

1. Read `lib/source_monitor/version.rb` to get the current VERSION.
2. Read the latest git tag with `git tag --sort=-v:refname | head -1`.
3. If the VERSION matches the latest tag (e.g., both are `0.3.2`), the version hasn't been bumped. Ask the user:
   - "Current version is X.Y.Z which already has a tag. What should the new version be?"
   - Offer options: patch (X.Y.Z+1), minor (X.Y+1.0), major (X+1.0.0), or custom.
   - Update `lib/source_monitor/version.rb` with the new version.
4. If VERSION is ahead of the latest tag, proceed with the current version.

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

## Step 4: Commit Version Bump + Changelog

Once both `lib/source_monitor/version.rb` (if changed) and `CHANGELOG.md` are updated:

1. Stage the changed files:
   ```
   git add lib/source_monitor/version.rb CHANGELOG.md
   ```
2. Create a single commit:
   ```
   chore: bump version to X.Y.Z and update changelog
   ```
   If only the changelog changed (version was already bumped), use:
   ```
   chore: update changelog for vX.Y.Z release
   ```

## Step 5: Create Release Branch and PR

1. Create a release branch: `git checkout -b release/vX.Y.Z`
2. Push the branch: `git push -u origin release/vX.Y.Z`
3. Generate a PR body from the new CHANGELOG.md entry (use the entry written in Step 3, not raw commits).
4. Create the PR using `gh pr create`:
   - Title: `Release vX.Y.Z`
   - Body format:
     ```
     ## Release vX.Y.Z

     <paste the CHANGELOG.md entry content here>

     ### Release Checklist
     - [x] Version bumped in `lib/source_monitor/version.rb`
     - [x] CHANGELOG.md updated
     - [ ] CI passes (lint, security, test, release_verification)

     ---
     Auto-generated release PR by `/release` command.
     ```
   - Base: `main`
5. Report the PR URL to the user.

## Step 6: Monitor CI Pipeline

Poll the CI status using `gh pr checks <PR_NUMBER> --watch` or repeated `gh pr checks <PR_NUMBER>` calls. The CI has 4 required jobs: `lint`, `security`, `test`, `release_verification`.

1. Tell the user: "Monitoring CI pipeline for PR #N... This typically takes 3-5 minutes."
2. Poll with `gh pr checks <PR_NUMBER>` every 30 seconds, up to 15 minutes.
3. After each poll, report progress if any jobs completed.

### If CI PASSES (all checks green):

Continue to Step 7.

### If CI FAILS:

1. Get the failure details: `gh pr checks <PR_NUMBER>` to identify which jobs failed.
2. For each failed job, fetch the log summary:
   ```
   gh run view <RUN_ID> --log-failed | tail -50
   ```
3. Present to the user:
   ```
   CI Failed on PR #N

   Failed Jobs:
   - <job_name>: <brief summary of failure>

   Log excerpt:
   <relevant log lines>
   ```
4. Ask the user what to do:
   - "Fix the issues and re-push" -- Help fix the issues, commit, push, and restart CI monitoring
   - "Close the PR and abort" -- Close the PR, delete the branch, switch back to main
   - "Investigate manually" -- Stop and let the user handle it

## Step 7: Auto-Merge PR

Once CI is green:

1. Merge the PR: `gh pr merge <PR_NUMBER> --merge --delete-branch`
2. Switch back to main and pull: `git checkout main && git pull origin main`
3. Report: "PR #N merged successfully."

## Step 8: Tag the Release

1. Create an annotated tag:
   ```
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   ```
2. Push the tag: `git push origin vX.Y.Z`
3. Create a GitHub release from the tag:
   ```
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "<changelog entry from Step 3>"
   ```
4. Report the release URL.

## Step 9: Build the Gem

1. Clean any old gem files: remove any `source_monitor-*.gem` files in the project root.
2. Build the gem: `gem build source_monitor.gemspec`
3. Verify the gem was built: check for `source_monitor-X.Y.Z.gem` in the project root.
4. Show the gem contents summary: `gem spec source_monitor-X.Y.Z.gem | head -30`

## Step 10: Gem Push Instructions

Present the final instructions to the user:

```
Release vX.Y.Z Complete!

  Git tag:    vX.Y.Z (pushed)
  GitHub:     <release URL>
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
- Always leave the user on the `main` branch in a clean state when possible.
