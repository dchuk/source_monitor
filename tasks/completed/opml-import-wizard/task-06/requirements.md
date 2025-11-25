#### Goals  

- Implement the Confirm step that shows a summary table of selected sources and the applied bulk settings for final review.  
- When confirmed, enqueue a background import job that creates sources individually, records per-source success/failure and skipped duplicates, and persists an ImportHistory record with results.  
- After job completion, ensure the user can view a static confirmation message on the Sources index with counts and a table of failures; guarantee that ImportHistory entries are queryable from the UI later.

#### Technical Considerations  

- Use Solid Queue for the import background job; the job should iterate selected sources, create sources individually (reusing Sources creation logic/service objects), capture and persist errors per source, and skip duplicates discovered by feed URL matching.  
- Create an ImportHistory ActiveRecord model/migration with JSONB columns for imported_sources, failed_sources, skipped_duplicates, bulk_settings, started_at and completed_at. Implement ImportHistory to reference the performing user using standard integer-based ActiveRecord IDs (i.e., user_id as an integer foreign key). Ensure migrations and model associations use Rails default integer id conventions rather than UUIDs.  
- Broadcast import completion via Turbo Streams (targeting Sources index or an ImportHistory feed) so users see static messaging and results; Ensure the static confirmation is available on next visit to Sources index even if the user navigated away during processing.  
- Ensure transactional and idempotency considerations for creation logic: handle ActiveRecord::RecordNotUnique or race conditions gracefully and record appropriate failure/skipped state.  
- Enforce admin-only access and strong parameter sanitization.

#### Dependencies  

- Implement OPML Import Wizard Shell  
- Add OPML Upload & Synchronous Parsing  
- Build Preview Table & Selection Persistence  
- Enqueue Health Checks & Turbo Stream UI  
- Bulk Settings Form Reusing Single Source Partial