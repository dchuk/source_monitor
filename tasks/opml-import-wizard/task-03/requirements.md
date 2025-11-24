#### Goals  

- Render a Preview step showing a paginated table of parsed sources with columns: feed URL, title, and "Already Imported" status.  
- Detect duplicates by matching feed URL against existing sourcemon_sources and mark duplicates as non-selectable.  
- Provide filters to toggle between "All", "New Sources", and "Existing Sources" and ensure selections persist across filter changes and step navigation.  
- Prevent progression to the next step if all sources are deselected and show a clear warning.

#### Technical Considerations  

- Implement the preview UI using Turbo Frames for the table and follow existing sources index patterns (search form targeting a turbo frame, Tailwind styling and accessibility conventions).  
- Store user selection state in ImportSession.selected_source_ids (JSONB) so selections persist across wizard steps and page navigations while the ImportSession exists. Ensure the ImportSession model uses an integer-based user reference (standard Rails user_id integer foreign key).  
- Duplicate detection uses only feed URL matching (as decided); malformed entries flagged by parsing step must be disabled for selection.  
- Implement server-side pagination for large parsed lists using existing pagination helpers used in the engine.

#### Dependencies  

- Add OPML Upload & Synchronous Parsing (parsing fills parsed_sources used to render preview)  
- Implement OPML Import Wizard Shell (routes, ImportSession persistence and wizard navigation)