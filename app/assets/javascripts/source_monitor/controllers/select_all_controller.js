import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "master",
    "item",
    "actionBar",
    "count",
    "crossPageBanner",
    "selectAllPagesInput",
  ];
  static values = { totalCandidates: Number };

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
    if (!checked) {
      this.deselectAllPages();
    }
    this.updateActionBar();
  }

  toggleItem() {
    this.deselectAllPages();
    this.syncMaster();
    this.updateActionBar();
  }

  selectAllPages() {
    if (this.hasSelectAllPagesInputTarget) {
      this.selectAllPagesInputTarget.disabled = false;
    }
    if (this.hasCrossPageBannerTarget) {
      this.crossPageBannerTarget.dataset.selected = "true";
      const deselect = this.crossPageBannerTarget.querySelector(
        "[data-role='deselect']"
      );
      const select = this.crossPageBannerTarget.querySelector(
        "[data-role='select']"
      );
      if (deselect) deselect.classList.remove("hidden");
      if (select) select.classList.add("hidden");
    }
    this.updateCount();
  }

  deselectAllPages() {
    if (this.hasSelectAllPagesInputTarget) {
      this.selectAllPagesInputTarget.disabled = true;
    }
    if (this.hasCrossPageBannerTarget) {
      this.crossPageBannerTarget.dataset.selected = "false";
      const deselect = this.crossPageBannerTarget.querySelector(
        "[data-role='deselect']"
      );
      const select = this.crossPageBannerTarget.querySelector(
        "[data-role='select']"
      );
      if (deselect) deselect.classList.add("hidden");
      if (select) select.classList.remove("hidden");
    }
    this.updateCount();
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
    this.updateCount();
    this.updateCrossPageBanner();
    if (checkedCount > 0) {
      this.actionBarTarget.classList.remove("hidden");
    } else {
      this.actionBarTarget.classList.add("hidden");
    }
  }

  updateCount() {
    if (!this.hasCountTarget) return;
    const isAllPages =
      this.hasCrossPageBannerTarget &&
      this.crossPageBannerTarget.dataset.selected === "true";
    if (isAllPages && this.hasTotalCandidatesValue) {
      this.countTarget.textContent = this.totalCandidatesValue;
    } else {
      const checkedCount = this.itemTargets.filter((cb) => cb.checked).length;
      this.countTarget.textContent = checkedCount;
    }
  }

  updateCrossPageBanner() {
    if (!this.hasCrossPageBannerTarget) return;
    const selectable = this.itemTargets.filter((cb) => !cb.disabled);
    const allChecked =
      selectable.length > 0 &&
      selectable.every((cb) => cb.checked);
    const hasMorePages =
      this.hasTotalCandidatesValue && this.totalCandidatesValue > selectable.length;

    if (allChecked && hasMorePages) {
      this.crossPageBannerTarget.classList.remove("hidden");
    } else {
      this.crossPageBannerTarget.classList.add("hidden");
      this.deselectAllPages();
    }
  }
}
