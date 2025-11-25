import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["master", "item"];

  connect() {
    this.syncMaster();
  }

  itemTargetConnected() {
    this.syncMaster();
  }

  itemTargetDisconnected() {
    this.syncMaster();
  }

  toggleAll(event) {
    const checked = event.target.checked;
    this.itemTargets.forEach((checkbox) => {
      if (checkbox.disabled) return;
      checkbox.checked = checked;
    });
  }

  toggleItem() {
    this.syncMaster();
  }

  syncMaster() {
    if (!this.hasMasterTarget) return;
    const selectable = this.itemTargets.filter((checkbox) => !checkbox.disabled);
    const allChecked = selectable.length > 0 && selectable.every((checkbox) => checkbox.checked);
    this.masterTarget.checked = allChecked;
  }
}
