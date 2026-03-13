import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["master", "item", "actionBar", "count"];

  connect() {
    this.syncMaster();
    this.updateActionBar();
  }

  itemTargetConnected() {
    this.syncMaster();
    this.updateActionBar();
  }

  itemTargetDisconnected() {
    this.syncMaster();
    this.updateActionBar();
  }

  toggleAll(event) {
    const checked = event.target.checked;
    this.itemTargets.forEach((checkbox) => {
      if (checkbox.disabled) return;
      checkbox.checked = checked;
    });
    this.updateActionBar();
  }

  toggleItem() {
    this.syncMaster();
    this.updateActionBar();
  }

  syncMaster() {
    if (!this.hasMasterTarget) return;
    const selectable = this.itemTargets.filter((checkbox) => !checkbox.disabled);
    const allChecked =
      selectable.length > 0 &&
      selectable.every((checkbox) => checkbox.checked);
    this.masterTarget.checked = allChecked;
  }

  updateActionBar() {
    if (!this.hasActionBarTarget) return;
    const checkedCount = this.itemTargets.filter((cb) => cb.checked).length;
    if (this.hasCountTarget) {
      this.countTarget.textContent = checkedCount;
    }
    if (checkedCount > 0) {
      this.actionBarTarget.classList.remove("hidden");
    } else {
      this.actionBarTarget.classList.add("hidden");
    }
  }
}
