## Objective

Enable users to bulk import feed sources via a wizard workflow that guides them through uploading an OPML file, previewing and selecting sources, running health checks, and configuring settings before importing—all from the Sources index page.

## Project Goal

Allow users to successfully import at least 90% of valid, healthy feeds from an OPML file in a single workflow, with less than 5% error rate due to invalid or duplicate sources.

## User Journey

1. **Entry Point**
    - User navigates to the Sources index page.
    - User clicks the new "Import OPML" button.

2. **Step 1: Upload OPML**
    - User is presented with a wizard step to upload an OPML file.
    - The system accepts any OPML file and parses it, handling errors gracefully.

3. **Step 2: Preview & Select Sources**
    - User sees a table listing all parsed sources from the OPML file.
    - The table includes a column indicating whether each source is "Already Imported."
    - Filters at the top allow toggling between "All," "New Sources," and "Existing Sources."
    - User can unselect any feeds they do not wish to import.
    - Selections persist as the user navigates between wizard steps.

4. **Step 3: Health Check**
    - The system runs a health check on each selected source’s feed URL.
    - Results are displayed in a table with a green check for healthy sources and a red X for unhealthy sources.
    - Unhealthy sources are unselected by default, but users can re-select them and proceed if desired.

5. **Step 4: Configure Settings**
    - User is presented with source settings (same options as single feed creation) to apply uniformly to all selected sources.
    - No per-feed override; settings apply to all selected feeds.

6. **Step 5: Confirm & Import**
    - User reviews the list of sources to be imported and confirms.
    - Import is initiated as a background job.
    - User is redirected to the Sources index page with a static confirmation message listing imported sources.
    - Fetching results and source health updates are shown in real-time via existing UI features.

## Features 

### In Scope
- OPML File Upload
- Wizard Workflow (Multi-step)
- Source Preview Table with Filters
- Duplicate Source Detection
- Source Selection Persistence
- Health Check for Feeds
- Bulk Source Settings Configuration
- Background Job for Import
- Static Import Confirmation

### Out of Scope
- Per-feed Settings Overrides
- Real-time Import Progress Bar
- OPML File Size or Structure Restrictions
- Advanced Error Recovery for Import Failures