import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    message: {
      type: String,
      default: "You have unsaved changes. Are you sure you want to leave this page?"
    }
  };

  connect() {
    this.boundBeforeUnload = this.beforeUnload.bind(this);
    this.boundTurboVisit = this.beforeTurboVisit.bind(this);

    window.addEventListener("beforeunload", this.boundBeforeUnload);
    document.addEventListener("turbo:before-visit", this.boundTurboVisit);
  }

  disconnect() {
    this.removeGuards();
  }

  disable() {
    this.removeGuards();
  }

  beforeUnload(event) {
    event.preventDefault();
    event.returnValue = this.messageValue;
    return this.messageValue;
  }

  beforeTurboVisit(event) {
    if (this.skipPrompt) return;

    if (!window.confirm(this.messageValue)) {
      event.preventDefault();
      return;
    }

    this.skipPrompt = true;
    this.removeGuards();
  }

  removeGuards() {
    window.removeEventListener("beforeunload", this.boundBeforeUnload);
    document.removeEventListener("turbo:before-visit", this.boundTurboVisit);
  }
}
