import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["menu"];
  static values = {
    hiddenClass: { type: String, default: "hidden" }
  };

  connect() {
    this._hideOnClickOutside = this.hide.bind(this);
    document.addEventListener("click", this._hideOnClickOutside);
  }

  disconnect() {
    document.removeEventListener("click", this._hideOnClickOutside);
  }

  toggle(event) {
    if (event) event.stopPropagation();
    if (!this.hasMenuTarget) return;
    this.menuTarget.classList.toggle(this.hiddenClassValue);
  }

  hide(event) {
    if (!this.hasMenuTarget) return;
    if (event && this.element.contains(event.target)) return;
    this.menuTarget.classList.add(this.hiddenClassValue);
  }
}
