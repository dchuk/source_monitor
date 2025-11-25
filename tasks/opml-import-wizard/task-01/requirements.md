#### Goals  

- Add an entry point on the Sources index page labeled "Import OPML" that navigates to a dedicated wizard route.  
- Implement a multi-step wizard shell with a left sidebar listing steps (Upload, Preview, Health Check, Configure, Confirm) and highlighting the current step.  
- Provide persistent per-step navigation and a JS warning when the user attempts to refresh or navigate away.  
- Implement server-side incremental persistence for wizard state via an ImportSession ActiveRecord model so later steps can update state.

#### Technical Considerations  

- Use a dedicated engine route and controller that follow a Wicked-style incremental update pattern for steps and render step content inside Turbo Frames.  
- Persist wizard state to an ImportSession record. Implement the ImportSession model and migration to reference the host user using standard integer-based ActiveRecord IDs (i.e., integer primary keys and a user reference using integer IDs). Ensure migrations use the default Rails integer id conventions (for example, t.references :user, foreign_key: true or equivalent) rather than UUID columns.  
- Store core placeholders in ImportSession (opml_file_metadata, parsed_sources, selected_source_ids, bulk_settings, current_step) as JSONB where appropriate.  
- Enforce admin-only access checks using existing SourceMonitor authentication hooks.  
- Provide graceful cancel/exit behavior that deletes the ImportSession and returns the user to the Sources index.  
- UI/UX must follow engine conventions: Tailwind styling, accessibility, and Turbo/Turbo Frames patterns used elsewhere in the codebase.

#### Dependencies  

- None