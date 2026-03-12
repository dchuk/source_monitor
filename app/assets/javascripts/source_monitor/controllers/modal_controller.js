import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["panel"];
  static classes = ["open"];
  static values = { autoOpen: Boolean, removeOnClose: Boolean };

  connect() {
    this.handleEscape = this.handleEscape.bind(this);
    if (this.autoOpenValue) {
      this.open();
    }
  }

  disconnect() {
    this.teardown();
  }

  open(event) {
    if (event) event.preventDefault();
    if (!this.hasPanelTarget) return;

    this.panelTarget.classList.remove("hidden");
    if (this.hasOpenClass) {
      this.panelTarget.classList.add(this.openClass);
    }

    document.body.classList.add("overflow-hidden");
    document.addEventListener("keydown", this.handleEscape);
  }

  close(event) {
    if (event) event.preventDefault();
    if (!this.hasPanelTarget) return;

    this.panelTarget.classList.add("hidden");
    if (this.hasOpenClass) {
      this.panelTarget.classList.remove(this.openClass);
    }

    this.teardown();

    if (this.removeOnCloseValue) {
      this.element.remove();
    }
  }

  backdrop(event) {
    if (event.target === event.currentTarget) {
      this.close(event);
    }
  }

  handleEscape(event) {
    if (event.key === "Escape") {
      this.close(event);
    }
  }

  teardown() {
    document.body.classList.remove("overflow-hidden");
    document.removeEventListener("keydown", this.handleEscape);
  }
}
