#### Goals  

- Provide a Health Check step that enqueues an individual background health-check job for each selected source.  
- Display a live-updating results table with status icons (healthy/unhealthy) updated via Turbo Streams as jobs complete.  
- Show a progress indicator (counts completed/total) and unselect unhealthy sources by default while allowing users to re-select them.  
- Block navigation forward if no healthy sources remain selected (unless user manually re-selects an unhealthy source).

#### Technical Considerations  

- Use Solid Queue for background jobs; create or reuse a HealthCheckJob that runs existing feed health check logic and broadcasts results on a Turbo Stream channel/topic for the ImportSession or user.  
- Store health check results back into ImportSession.parsed_sources entries (health_status, error) so step state is persistent and viewable if refreshed while session exists. Ensure ImportSession is implemented with a standard integer-based user reference (user_id as integer).  
- Implement server-side cancellation semantics: if the user navigates away from the health-check step before all jobs finish, mark in ImportSession and ensure any remaining jobs do not update transient UI state or re-broadcast for an expired session.  
- Ensure progress updates and row updates follow the engine’s Turbo Streams conventions and use existing broadcasters patterns.

#### Dependencies  

- Build Preview Table & Selection Persistence (selected set to health-check)