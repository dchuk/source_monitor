/* global MutationObserver, requestAnimationFrame, cancelAnimationFrame */
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    maxVisible: { default: 3, type: Number },
    expanded: { default: false, type: Boolean }
  };

  static targets = ["list", "badge", "badgeCount", "clearAll"];

  connect() {
    this.rafId = null;
    this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    this.boundScheduleRecalculate = () => this.scheduleRecalculate();

    this.observer = new MutationObserver(this.boundScheduleRecalculate);
    this.observer.observe(this.listTarget, { childList: true });

    this.listTarget.addEventListener(
      "notification:dismissed",
      this.boundScheduleRecalculate
    );

    this.recalculateVisibility();
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }

    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }

    this.listTarget.removeEventListener(
      "notification:dismissed",
      this.boundScheduleRecalculate
    );
    document.removeEventListener("click", this.boundHandleClickOutside);
  }

  scheduleRecalculate() {
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
    }
    this.rafId = requestAnimationFrame(() => {
      this.rafId = null;
      this.recalculateVisibility();
    });
  }

  recalculateVisibility() {
    const toasts = Array.from(this.listTarget.children);
    const total = toasts.length;

    if (this.expandedValue) {
      toasts.forEach((toast) => {
        toast.classList.remove("hidden");
        toast.removeAttribute("aria-hidden");
        toast.removeAttribute("inert");
      });
    } else {
      toasts.forEach((toast, index) => {
        if (index < this.maxVisibleValue) {
          toast.classList.remove("hidden");
          toast.removeAttribute("aria-hidden");
          toast.removeAttribute("inert");
        } else {
          toast.classList.add("hidden");
          toast.setAttribute("aria-hidden", "true");
          toast.setAttribute("inert", "");
        }
      });
    }

    const hiddenCount = this.expandedValue
      ? 0
      : Math.max(0, total - this.maxVisibleValue);

    if (this.hasBadgeTarget) {
      if (this.hasBadgeCountTarget) {
        this.badgeCountTarget.textContent = `+${hiddenCount} more`;
      }
      if (hiddenCount > 0) {
        this.badgeTarget.classList.remove("hidden");
      } else {
        this.badgeTarget.classList.add("hidden");
      }
    }

    if (this.hasClearAllTarget) {
      const showClearAll = total > 0 && (hiddenCount > 0 || this.expandedValue);
      if (showClearAll) {
        this.clearAllTarget.classList.remove("hidden");
      } else {
        this.clearAllTarget.classList.add("hidden");
      }
    }
  }

  toggleExpand(event) {
    event.preventDefault();
    if (this.expandedValue) {
      this.collapseStack();
    } else {
      this.expandStack();
    }
  }

  expandStack() {
    this.expandedValue = true;
    this.recalculateVisibility();
    document.addEventListener("click", this.boundHandleClickOutside);
  }

  collapseStack() {
    this.expandedValue = false;
    document.removeEventListener("click", this.boundHandleClickOutside);
    this.recalculateVisibility();
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.collapseStack();
    }
  }

  clearAll(event) {
    event.preventDefault();
    const toasts = Array.from(this.listTarget.children);
    toasts.forEach((toast) => toast.remove());
    this.collapseStack();
  }
}
