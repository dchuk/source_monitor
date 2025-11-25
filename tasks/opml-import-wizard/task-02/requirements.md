#### Goals  

- Implement the Upload step form that accepts OPML files and validates file type before parsing.  
- Parse OPML synchronously in the request, extract feed entries, and persist parsed entries into the ImportSession.parsed_sources JSONB field.  
- Mark malformed or unparsable entries clearly (status + error message) so they are excluded from selection in Preview.  
- Block navigation to the Preview step until at least one valid parsed entry exists.

#### Technical Considerations  

- Use existing Feedjira/Nokogiri parsing patterns where available; parse synchronously in controller action handling the Upload step and store parsed results in ImportSession.parsed_sources.  
- Validate content-type and fallback to XML parsing based on file contents; present actionable error messages for invalid files or malformed XML.  
- Ensure the ImportSession model and migration reference the user via standard integer-based ActiveRecord IDs (i.e., integer primary keys and an integer user reference). Do not introduce UUID columns for user references—use the Rails default integer id and foreign key conventions.  
- For large files, ensure the request handles a reasonable file size and the preview UI will paginate large parsed lists (pagination handled in Preview task). Synchronous parsing chosen deliberately for immediate feedback.  
- Respect security and file handling conventions in the engine (tempfiles, permitted params, user scoping).

#### Dependencies  

- Implement OPML Import Wizard Shell (needed for routes, ImportSession persistence and step navigation)