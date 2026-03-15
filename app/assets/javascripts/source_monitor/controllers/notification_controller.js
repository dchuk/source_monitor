import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    delay: { default: 5000, type: Number }
  };

  connect() {
    this.clearTimeout();
    this.applyLevelDelay();
    this.startTimer();
  }

  disconnect() {
    this.clearTimeout();
  }

  hide(event) {
    if (event) event.preventDefault();
    this.clearTimeout();
    this.dismiss();
  }

  startTimer() {
    if (this.delayValue <= 0) return;
    this.timeoutId = window.setTimeout(() => this.dismiss(), this.delayValue);
  }

  applyLevelDelay() {
    // Error delay is set server-side via TOAST_DURATION_ERROR (6000ms) in
    // ApplicationController and passed as data-notification-delay-value.
    // No client-side override needed.
  }

  dismiss() {
    if (!this.element) return;
    this.element.dispatchEvent(
      new CustomEvent("notification:dismissed", { bubbles: true })
    );
    this.element.classList.add("opacity-0", "translate-y-2");
    window.setTimeout(() => {
      if (this.element && this.element.remove) {
        this.element.remove();
      }
    }, 200);
  }

  clearTimeout() {
    if (!this.timeoutId) return;

    window.clearTimeout(this.timeoutId);
    this.timeoutId = null;
  }
}
