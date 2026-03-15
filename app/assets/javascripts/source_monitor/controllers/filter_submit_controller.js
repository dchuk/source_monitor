import { Controller } from "@hotwired/stimulus";

// Submits the parent form when a filter dropdown value changes.
// Replaces inline `onchange="this.form.requestSubmit()"` handlers.
//
// Usage:
//   <select data-action="change->filter-submit#submit">
export default class extends Controller {
  submit(event) {
    const form = event.target.closest("form");
    if (form) form.requestSubmit();
  }
}
