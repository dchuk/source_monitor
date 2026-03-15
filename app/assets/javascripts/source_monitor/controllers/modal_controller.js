import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["panel"];
  static classes = ["open"];
  static values = { autoOpen: Boolean, removeOnClose: Boolean };

  connect() {
    this.handleEscape = this.handleEscape.bind(this);
    this._inertElements = [];
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

    // Focus trap: set inert on sibling elements so Tab stays inside the modal
    this._setInert(true);

    // Move focus to the first focusable element inside the modal
    this._focusFirstElement();
  }

  close(event) {
    if (event) event.preventDefault();
    if (!this.hasPanelTarget) return;

    this.panelTarget.classList.add("hidden");
    if (this.hasOpenClass) {
      this.panelTarget.classList.remove(this.openClass);
    }

    // Remove inert from background elements
    this._setInert(false);
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

  // -- Private helpers --

  _setInert(inert) {
    if (inert) {
      // Find the modal panel's topmost parent that is a direct child of body,
      // then mark all its siblings as inert
      const modalRoot = this._findModalRoot();
      if (!modalRoot) return;

      this._inertElements = [];
      for (const sibling of document.body.children) {
        if (sibling === modalRoot || sibling === this.element) continue;
        if (sibling.nodeType !== Node.ELEMENT_NODE) continue;
        if (!sibling.hasAttribute("inert")) {
          sibling.setAttribute("inert", "");
          this._inertElements.push(sibling);
        }
      }
    } else {
      for (const el of this._inertElements) {
        el.removeAttribute("inert");
      }
      this._inertElements = [];
    }
  }

  _findModalRoot() {
    // Walk up from the panel target to find the element that is a direct child of body
    let el = this.hasPanelTarget ? this.panelTarget : this.element;
    while (el && el.parentElement !== document.body) {
      el = el.parentElement;
    }
    return el;
  }

  _focusFirstElement() {
    // Defer to next frame so the panel is visible
    requestAnimationFrame(() => {
      if (!this.hasPanelTarget) return;
      const focusable = this.panelTarget.querySelector(
        'button, [href], input:not([type="hidden"]), select, textarea, [tabindex]:not([tabindex="-1"])'
      );
      if (focusable) focusable.focus();
    });
  }
}
