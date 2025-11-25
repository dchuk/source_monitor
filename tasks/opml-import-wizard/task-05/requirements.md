#### Goals  

- Implement the Configure step that displays the exact same input fields as the single source creation form, applied uniformly to all selected sources.  
- Persist validated bulk settings into ImportSession.bulk_settings so they carry forward to the Confirm step and are applied during import.  
- Validate required fields and prevent progression until the form is valid.

#### Technical Considerations  

- Reuse the existing single-source form partial to render fields and validation messages; adapt controller params mapping to persist the resulting bulk settings JSON into ImportSession.bulk_settings. Ensure ImportSession uses an integer-based user reference (standard Rails user_id integer foreign key).  
- Use the engine's existing parameter sanitization and validation patterns for source attributes.  
- Ensure the form is accessible and styled with Tailwind consistent with the rest of the engine.  
- Disallow per-feed overrides in this release; the stored settings apply uniformly to all selected sources during import.

#### Dependencies  

- Enqueue Health Checks & Turbo Stream UI (health results determine which sources are in the target set)  
- Implement OPML Import Wizard Shell (wizard rendering and step navigation)